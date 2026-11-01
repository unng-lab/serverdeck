import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/hosting/authority.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:test/test.dart';

import 'authority_test.dart' as foundation;

Matcher failure(String code) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', code));
Future<void> settle() => foundation.settle();
String nonce(int byte) =>
    base64Url.encode(List.filled(32, byte)).replaceAll('=', '');

final class Channel implements VerifiedMcpChannel {
  Channel(this.ownerIdentity, this.appRoot, this.buildId);
  @override
  String ownerIdentity, appRoot, buildId;
  int proofs = 0;
  Object? proofError;
  Object? logicalProofError;
  Completer<void>? pause;
  @override
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    proofs++;
    final actual = pause?.future ?? Future<void>.value();
    observeNativeCompletion?.call(actual);
    if (logicalProofError != null) throw logicalProofError!;
    await actual;
    if (proofError != null) throw proofError!;
  }

  @override
  Future<Uint8List> read({required int count, required Duration deadline}) =>
      throw StateError('NO_IO_IN_UNIT');
  @override
  Future<void> write(List<int> bytes, {required Duration deadline}) =>
      throw StateError('NO_IO_IN_UNIT');
  @override
  Future<void> drainOutput({required Duration deadline}) =>
      throw StateError('NO_IO_IN_UNIT');
  @override
  Future<void> disconnect() => throw StateError('NO_IO_IN_UNIT');
}

final class Setup {
  final runtime = foundation.Runtime(), lease = foundation.Lease();
  late HostAuthority host;
  late EngineSessions sessions;
  Duration elapsed = Duration.zero;
  static Future<Setup> create({void Function(String)? onExpiredChannel}) async {
    final s = Setup();
    s.host = foundation.prepare(s.runtime, s.lease);
    await s.host.initialize();
    s.sessions = EngineSessions.withAuthority(
      authority: s.host,
      admissionBlocked: () => false,
      elapsed: () => s.elapsed,
      onExpiredChannel: onExpiredChannel,
    );
    return s;
  }

  Channel channel() =>
      Channel(runtime.ownerIdentity, runtime.appRoot, runtime.buildId);
  Future<OwnerSession> owner([Object? binding]) async =>
      sessions.openOwner(await host.bindOwner(binding ?? Object()));
  Future<void> close() async {
    await sessions.close();
    await host.close();
    expect(lease.closes, 0);
  }
}

Future<OperationalAuthenticated> authenticate(
  Setup s,
  String id,
  Channel channel,
) async {
  final token = List<int>.filled(32, 7);
  final handshake = McpServerHandshake(
    peer: channel,
    token: token,
    channel: id,
    sessions: s.sessions,
  );
  token.fillRange(0, token.length, 0); // Constructor must own its captured key.
  final hello = await handshake.hello();
  expect(hello.clientRole, OperationalRole.mcp);
  final transcript = OperationalBootstrapTranscript(
    hello: hello,
    clientNonce: nonce(9),
    requestedCapabilities: ['mcp'],
  );
  final key = SecretKeyData(
    List<int>.filled(32, 7),
    overwriteWhenDestroyed: true,
  );
  late final String mac;
  try {
    mac = base64Url
        .encode(
          DartHmac.sha256()
              .calculateMacSync(
                transcript.clientBytes(),
                secretKeyData: key,
                nonce: [],
              )
              .bytes,
        )
        .replaceAll('=', '');
  } finally {
    key.destroy();
  }
  return handshake.authenticate(
    StrictCodec().encode(
      OperationalAuthenticate(
        clientNonce: nonce(9),
        clientBuildId: hello.buildId,
        requestedCapabilities: ['mcp'],
        proof: mac,
      ).toJson(),
      maxBytes: 4096,
    ),
  );
}

void main() {
  test(
    'nested detach pause cannot resume or admit work before retirement returns',
    () async {
      final s = await Setup.create();
      final capability = await s.host.bindOwner(Object());
      final owner = await s.sessions.openOwner(capability);
      SessionAdmissionPause? nested;
      Future<void>? blocked;
      var reentered = false;
      s.sessions.onSessionDetached((_) {
        if (reentered) return;
        reentered = true;
        nested = s.sessions.pauseAdmission();
        expect(() => s.sessions.resumeAdmission(nested!), failure('NOT_READY'));
        blocked = expectLater(
          s.sessions.openOwner(capability),
          failure('NOT_READY'),
        );
      });
      final outer = s.sessions.pauseAdmission();
      await blocked;
      await settle();
      expect(owner.isCurrent, isFalse);
      expect(s.sessions.count, 0);
      expect(identical(outer, nested), isTrue);
      // The outer caller receives the latest fence, not an unusable stale one.
      s.sessions.resumeAdmission(outer);
      expect((await s.sessions.openOwner(capability)).isCurrent, isTrue);
      await s.close();
    },
  );

  test(
    'uncaught nested resume refusal makes retirement failure permanent',
    () async {
      final s = await Setup.create();
      await s.owner();
      s.sessions.onSessionDetached((_) {
        final nested = s.sessions.pauseAdmission();
        s.sessions.resumeAdmission(nested);
      });
      expect(() => s.sessions.pauseAdmission(), failure('SERVICE_UNAVAILABLE'));
      expect(s.sessions.count, 0);
      await expectLater(s.owner(), failure('SERVICE_UNAVAILABLE'));
      await s.close();
    },
  );

  test('admission pause retires owner and MCP interests without replacing registry', () async {
    final s = await Setup.create();
    final owner = await s.owner();
    final auth = await authenticate(s, 'before-pause', s.channel());
    final detached = <String>[];
    s.sessions.onSessionDetached(detached.add);
    final pause = s.sessions.pauseAdmission();
    expect(s.sessions.count, 0);
    expect(owner.isCurrent, isFalse);
    expect(detached.length, 2);
    expect(() => owner.reserve('settings.get'), failure('UNAUTHORIZED'));
    expect(
      () => s.sessions.reserve('before-pause', auth.sessionId, 'session.ping'),
      failure('UNAUTHORIZED'),
    );
    await expectLater(s.owner(), failure('NOT_READY'));
    s.sessions.resumeAdmission(pause);
    expect(owner.isCurrent, isFalse);
    expect(
      () => s.sessions.reserve('before-pause', auth.sessionId, 'session.ping'),
      failure('UNAUTHORIZED'),
    );
    final replacement = await s.owner();
    expect(replacement.isCurrent, isTrue);
    expect(replacement.generation, owner.generation);
    await authenticate(s, 'after-pause', s.channel());
    expect(s.sessions.count, 2);
    await s.close();
  });

  test('only current same-registry pause can reopen admission once', () async {
    final s = await Setup.create(), other = await Setup.create();
    final old = s.sessions.pauseAdmission();
    final current = s.sessions.pauseAdmission();
    final foreign = other.sessions.pauseAdmission();
    expect(() => s.sessions.resumeAdmission(old), failure('NOT_READY'));
    expect(() => s.sessions.resumeAdmission(foreign), failure('NOT_READY'));
    await expectLater(s.owner(), failure('NOT_READY'));
    s.sessions.resumeAdmission(current);
    expect(() => s.sessions.resumeAdmission(current), failure('NOT_READY'));
    expect((await s.owner()).isCurrent, isTrue);
    other.sessions.resumeAdmission(foreign);
    await s.close();
    await other.close();
  });

  test('late pending owner proof cannot cross pause and resume', () async {
    final s = await Setup.create();
    final capability = await s.host.bindOwner(Object());
    final physical = s.runtime.paused = Completer<void>();
    final opening = s.sessions.openOwner(capability);
    final failed = expectLater(opening, failure('NOT_READY'));
    await settle();
    final pause = s.sessions.pauseAdmission();
    s.sessions.resumeAdmission(pause);
    s.runtime.paused = null;
    physical.complete();
    await failed;
    expect(s.sessions.count, 0);
    expect((await s.sessions.openOwner(capability)).isCurrent, isTrue);
    await s.close();
  });

  test('late proof of existing owner cannot return it after resume', () async {
    final s = await Setup.create();
    final capability = await s.host.bindOwner(Object());
    final old = await s.sessions.openOwner(capability);
    final physical = s.runtime.paused = Completer<void>();
    final opening = s.sessions.openOwner(capability);
    final failed = expectLater(opening, failure('NOT_READY'));
    await settle();
    final pause = s.sessions.pauseAdmission();
    s.sessions.resumeAdmission(pause);
    s.runtime.paused = null;
    physical.complete();
    await failed;
    expect(old.isCurrent, isFalse);
    expect(s.sessions.count, 0);
    await s.close();
  });

  test('late MCP handshake proof cannot register after resume', () async {
    final s = await Setup.create(), channel = s.channel();
    final physical = channel.pause = Completer<void>();
    final opening = authenticate(s, 'late-handshake', channel);
    final failed = expectLater(opening, failure('UNAUTHORIZED'));
    await settle();
    final pause = s.sessions.pauseAdmission();
    s.sessions.resumeAdmission(pause);
    physical.complete();
    await failed;
    expect(s.sessions.count, 0);
    await authenticate(s, 'new-handshake', s.channel());
    expect(s.sessions.mcpCount, 1);
    await s.close();
  });

  test(
    'pause retires request interest but retains physical proof drain',
    () async {
      final s = await Setup.create();
      final owner = await s.owner();
      final request = owner.reserve('settings.get');
      final physical = s.runtime.paused = Completer<void>();
      final proving = request.revalidate();
      final failed = expectLater(proving, failure('UNAUTHORIZED'));
      await settle();
      final pause = s.sessions.pauseAdmission();
      s.sessions.resumeAdmission(pause);
      var drained = false;
      final closing = s.sessions.close().then((_) => drained = true);
      await settle();
      expect(drained, isFalse);
      s.runtime.paused = null;
      physical.complete();
      await failed;
      await closing;
      expect(drained, isTrue);
      await s.host.close();
    },
  );

  test('failed retirement cannot be resumed as a successful pause', () async {
    final s = await Setup.create();
    await s.owner();
    final prior = s.sessions.pauseAdmission();
    s.sessions.resumeAdmission(prior);
    final owner = await s.owner();
    s.sessions.onSessionDetached((_) => throw StateError('PRIVATE_CALLBACK'));
    expect(() => s.sessions.pauseAdmission(), failure('SERVICE_UNAVAILABLE'));
    expect(owner.isCurrent, isFalse);
    expect(
      () => s.sessions.resumeAdmission(prior),
      failure('SERVICE_UNAVAILABLE'),
    );
    await expectLater(s.owner(), failure('SERVICE_UNAVAILABLE'));
    await s.close();
  });

  test('permanent stop wins over a current pause token', () async {
    final s = await Setup.create();
    final pause = s.sessions.pauseAdmission();
    s.sessions.stop();
    expect(
      () => s.sessions.resumeAdmission(pause),
      failure('SERVICE_UNAVAILABLE'),
    );
    await expectLater(s.owner(), failure('SERVICE_UNAVAILABLE'));
    await s.close();
  });

  test(
    'registration expiry callback cannot admit a proof from before pause',
    () async {
      late Setup s;
      var paused = 0;
      s = await Setup.create(
        onExpiredChannel: (_) {
          final pause = s.sessions.pauseAdmission();
          paused++;
          s.sessions.resumeAdmission(pause);
        },
      );
      await s.owner();
      final capability = await s.host.bindOwner(Object());
      // The record expires after openOwner's initial sweep, during its proof.
      s.runtime.onProof = () => s.elapsed = const Duration(seconds: 61);
      await expectLater(s.sessions.openOwner(capability), failure('NOT_READY'));
      expect(paused, 1);
      expect(s.sessions.count, 0);
      s.runtime.onProof = null;
      expect((await s.sessions.openOwner(capability)).isCurrent, isTrue);
      await s.close();
    },
  );

  test('operation snapshot drain owns late MCP phases beyond logical failure', () async {
    final s = await Setup.create(), channel = s.channel();
    final authentication = await authenticate(s, 'late-chain', channel);
    final request = s.sessions.reserve(
      'late-chain',
      authentication.sessionId,
      'session.ping',
    );
    final first = s.runtime.paused = Completer<void>();
    final physicalChannel = channel.pause = Completer<void>();
    channel.logicalProofError = StateError('TIMEOUT');
    final observed = <Future<void>>{};
    var physicalErrors = 0;
    final proving = request.revalidate(
      observeNativeCompletion: (actual) {
        observed.add(
          actual.then<void>(
            (_) {},
            onError: (Object _, StackTrace __) {
              physicalErrors++;
            },
          ),
        );
      },
    );
    await settle();
    await expectLater(
      proving.timeout(Duration.zero),
      throwsA(isA<TimeoutException>()),
    );
    final failed = expectLater(proving, failure('UNAUTHORIZED'));
    request.complete();
    var drained = false;
    // Same snapshot shape as read/connect actors, taken before channel exists.
    final drain = Future.wait<void>(observed.toList())
        .then((_) => drained = true);
    final before = channel.proofs;
    s.runtime.paused = null;
    first.complete();
    await failed;
    await settle();
    expect(channel.proofs, greaterThan(before));
    expect(drained, isFalse);
    var closed = false;
    final closing = s.sessions.close().then((_) => closed = true);
    await settle();
    expect(closed, isFalse);
    physicalChannel.complete();
    await drain;
    expect(
      physicalErrors,
      0,
    ); // A logical timeout is not a native-work failure.
    await closing;
    await s.host.close();
  });

  test(
    'all8 expired records are reclaimed before owner capacity refusal',
    () async {
      final s = await Setup.create();
      final caps = <OwnerCapability>[], owners = <OwnerSession>[];
      for (var i = 0; i < 8; i++) {
        caps.add(await s.host.bindOwner(Object()));
        owners.add(await s.sessions.openOwner(caps.last));
      }
      s.elapsed = const Duration(seconds: 61);
      final replacement = await s.sessions.openOwner(caps.first);
      expect(replacement.isCurrent, isTrue);
      expect(s.sessions.count, 1);
      expect(owners.every((owner) => !owner.isCurrent), isTrue);
      await s.close();
    },
  );

  test(
    'capacity accounts live and pending owners after expired cleanup',
    () async {
      final s = await Setup.create();
      final caps = [
        for (var i = 0; i < 8; i++) await s.host.bindOwner(Object()),
      ];
      for (final cap in caps.take(2)) await s.sessions.openOwner(cap);
      s.elapsed = const Duration(seconds: 30);
      for (final cap in caps.skip(2).take(3)) await s.sessions.openOwner(cap);
      s.elapsed = const Duration(seconds: 61);
      final pause = s.runtime.paused = Completer<void>();
      final pending = [
        for (final cap in [caps[0], caps[1], ...caps.skip(5)])
          s.sessions.openOwner(cap),
      ];
      expect(identical(s.sessions.openOwner(caps[0]), pending.first), isTrue);
      expect(s.sessions.count, 3);
      pause.complete();
      final issued = await Future.wait(pending);
      expect(issued.every((owner) => owner.isCurrent), isTrue);
      expect(s.sessions.count, 8);
      await s.close();
    },
  );

  test('expiry callback exceptions are safe Future failures and callback stop is final', () async {
    final s = await Setup.create(
      onExpiredChannel: (_) => throw StateError('private callback details'),
    );
    final cap = await s.host.bindOwner(Object());
    await s.sessions.openOwner(cap);
    s.elapsed = const Duration(seconds: 61);
    await expectLater(s.sessions.openOwner(cap), failure('UNAUTHORIZED'));
    expect(s.sessions.count, 0);
    await s.close();
    late Setup stopped;
    stopped = await Setup.create(
      onExpiredChannel: (_) => stopped.sessions.stop(),
    );
    final otherCap = await stopped.host.bindOwner(Object());
    await stopped.sessions.openOwner(otherCap);
    stopped.elapsed = const Duration(seconds: 61);
    await expectLater(
      stopped.sessions.openOwner(otherCap),
      failure('SERVICE_UNAVAILABLE'),
    );
    expect(stopped.sessions.count, 0);
    await stopped.close();
  });

  test('owner root helper retains physical proof after response timeout and completion', () async {
    final s = await Setup.create(), owner = await s.owner();
    final request = owner.reserve('grants.configuration');
    await owner.admit(request);
    final pause = s.runtime.paused = Completer<void>();
    final root = request.verifiedOwnerBundleRoot();
    await settle();
    await expectLater(
      root.timeout(Duration.zero),
      throwsA(isA<TimeoutException>()),
    );
    final lateFailure = expectLater(root, throwsA(isA<StateError>()));
    request.complete();
    var closed = false;
    final closing = s.sessions.close().then((_) => closed = true);
    await settle();
    expect(closed, isFalse);
    pause.complete();
    await lateFailure;
    await closing;
    await s.host.close();
  });

  test(
    'aggregate256 bound includes proofs of already disconnected MCP records',
    () async {
      final s = await Setup.create();
      final fresh = await authenticate(s, 'fresh', s.channel());
      final pauses = <Completer<void>>[], failures = <Future<void>>[];
      for (var wave = 0; wave < 4; wave++) {
        for (var i = 0; i < 4; i++) {
          final id = 'wave-$wave-$i', channel = s.channel();
          final authentication = await authenticate(s, id, channel);
          final pause = channel.pause = Completer<void>();
          pauses.add(pause);
          for (var r = 0; r < 16; r++) {
            final request = s.sessions.reserve(
              id,
              authentication.sessionId,
              'session.ping',
            );
            final before = channel.proofs;
            failures.add(
              expectLater(request.revalidate(), failure('UNAUTHORIZED')),
            );
            for (var tick = 0; tick < 50 && channel.proofs == before; tick++) {
              await Future<void>.value();
            }
            expect(channel.proofs, greaterThan(before));
            request.complete();
          }
          s.sessions.disconnect(id);
        }
      }
      expect(
        () => s.sessions.reserve('fresh', fresh.sessionId, 'session.ping'),
        failure('RESOURCE_LIMIT'),
      );
      final before = s.runtime.proofs;
      final extra = McpServerHandshake(
        peer: s.channel(),
        token: List.filled(32, 7),
        channel: 'over-capacity',
        sessions: s.sessions,
      );
      await expectLater(extra.hello(), failure('UNAUTHORIZED'));
      expect(s.runtime.proofs, before);
      var closed = false;
      final closing = s.sessions.close().then((_) => closed = true);
      await settle();
      expect(closed, isFalse);
      for (final pause in pauses) pause.complete();
      await Future.wait(failures);
      await closing;
      await s.host.close();
    },
  );

  test('owner admission requires Host capability and cannot be reconstructed from strings', () async {
    final s = await Setup.create();
    final owner = await s.owner();
    final request = owner.reserve('settings.get');
    expect(request.initialAdmissionProved, isFalse);
    await expectLater(
      s.sessions.begin(request.channel, request.sessionId, 'settings.get'),
      failure('UNAUTHORIZED'),
    );
    await owner.admit(request);
    expect(request.initialAdmissionProved, isTrue);
    expect(request.role, OperationalRole.owner);
    expect(() => owner.reserve('mcp.open'), failure('FORBIDDEN'));
    request.complete();
    await request.settled;
    owner.close();
    expect(() => owner.reserve('settings.get'), failure('UNAUTHORIZED'));
    await s.close();
  });

  test(
    'foreign capability and duplicate registry cannot issue owner authority',
    () async {
      final s = await Setup.create(), other = await Setup.create();
      final capability = await other.host.bindOwner(Object());
      await expectLater(
        s.sessions.openOwner(capability),
        failure('UNAUTHORIZED'),
      );
      expect(s.sessions.count, 0);
      expect(
        () => EngineSessions.withAuthority(
          authority: s.host,
          admissionBlocked: () => false,
        ),
        failure('NOT_READY'),
      );
      final owner = await s.owner();
      expect(owner.isCurrent, isTrue);
      await s.close();
      await other.close();
    },
  );

  test(
    'pending issuance and repeated open cannot revive a detached owner session',
    () async {
      final s = await Setup.create(), binding = Object();
      final capability = await s.host.bindOwner(binding);
      final owner = await s.sessions.openOwner(capability);
      final pause = s.runtime.paused = Completer<void>();
      final repeated = s.sessions.openOwner(capability);
      final denied = expectLater(repeated, failure('UNAUTHORIZED'));
      owner.close();
      pause.complete();
      await denied;
      s.runtime.paused = null;
      final newBinding = Object(),
          newCapability = await s.host.bindOwner(newBinding);
      final pause2 = s.runtime.paused = Completer<void>();
      final pending = s.sessions.openOwner(newCapability);
      final rejected = expectLater(pending, failure('UNAUTHORIZED'));
      s.host.detachOwner(newBinding);
      pause2.complete();
      await rejected;
      expect(s.sessions.count, 0);
      await s.close();
    },
  );

  test('completed request retains16 admission charges and close drain until physical proof', () async {
    final s = await Setup.create(), owner = await s.owner();
    final pause = s.runtime.paused = Completer<void>();
    final work = <Future<void>>[];
    for (var i = 0; i < 16; i++) {
      final request = owner.reserve('settings.get');
      final proving = request.revalidate();
      work.add(expectLater(proving, failure('UNAUTHORIZED')));
      await settle();
      request.complete();
    }
    expect(() => owner.reserve('settings.get'), failure('RESOURCE_LIMIT'));
    var closed = false;
    final closing = s.sessions.close().then((_) => closed = true);
    await settle();
    expect(closed, isFalse);
    pause.complete();
    await Future.wait(work);
    await closing;
    expect(closed, isTrue);
    await s.host.close();
  });

  test(
    'expired owner session needs fresh issuance without renewing old operation',
    () async {
      final s = await Setup.create();
      final cap = await s.host.bindOwner(Object()),
          owner = await s.sessions.openOwner(cap);
      s.elapsed = const Duration(seconds: 61);
      expect(() => owner.reserve('settings.get'), failure('UNAUTHORIZED'));
      final renewed = await s.sessions.openOwner(cap);
      expect(identical(renewed, owner), isFalse);
      expect(s.sessions.count, 1);
      await s.close();
    },
  );

  test('external authenticated channel is MCP-only and cannot invoke owner methods', () async {
    final s = await Setup.create();
    final authenticated = await authenticate(s, 'mcp-unit', s.channel());
    expect(authenticated.clientRole, OperationalRole.mcp);
    expect(s.sessions.mcpCount, 1);
    final request = await s.sessions.begin(
      'mcp-unit',
      authenticated.sessionId,
      'session.ping',
    );
    expect(request.role, OperationalRole.mcp);
    expect(request.initialAdmissionProved, isTrue);
    request.complete();
    await expectLater(
      s.sessions.begin('mcp-unit', authenticated.sessionId, 'settings.get'),
      failure('FORBIDDEN'),
    );
    await expectLater(
      s.sessions.begin('mcp-unit', authenticated.sessionId, 'mcp.invoke'),
      failure('FORBIDDEN'),
    );
    await s.close();
  });

  test('wire owner capability request is rejected even with correct build identity', () async {
    final s = await Setup.create();
    final handshake = McpServerHandshake(
      peer: s.channel(),
      token: List.filled(32, 7),
      channel: 'forged',
      sessions: s.sessions,
    );
    final hello = await handshake.hello();
    final forged = OperationalAuthenticate(
      clientNonce: nonce(9),
      clientBuildId: hello.buildId,
      requestedCapabilities: ['owner'],
      proof: nonce(7),
    );
    await expectLater(
      handshake.authenticate(
        StrictCodec().encode(forged.toJson(), maxBytes: 4096),
      ),
      failure('UNAUTHORIZED'),
    );
    expect(s.sessions.count, 0);
    await s.close();
  });

  test(
    'changed peer owner/root/build fails closed before registration',
    () async {
      for (final field in ['owner', 'root', 'build']) {
        final s = await Setup.create(), channel = s.channel();
        final handshake = McpServerHandshake(
          peer: channel,
          token: List.filled(32, 7),
          channel: field,
          sessions: s.sessions,
        );
        await handshake.hello();
        switch (field) {
          case 'owner':
            channel.ownerIdentity += '-other';
          case 'root':
            channel.appRoot += '/other';
          case 'build':
            channel.buildId = '${'c' * 40}+Release+${'d' * 64}';
        }
        await expectLater(
          handshake.authenticate(
            StrictCodec().encode(
              OperationalAuthenticate(
                clientNonce: nonce(9),
                clientBuildId: s.runtime.buildId,
                requestedCapabilities: ['mcp'],
                proof: nonce(7),
              ).toJson(),
              maxBytes: 4096,
            ),
          ),
          failure('UNAUTHORIZED'),
        );
        expect(s.sessions.count, 0);
        await s.close();
      }
    },
  );

  test(
    'MCP cap remains4 and total session cap remains8 including local owners',
    () async {
      final s = await Setup.create();
      for (var i = 0; i < 4; i++) await authenticate(s, 'mcp-$i', s.channel());
      await expectLater(
        authenticate(s, 'fifth', s.channel()),
        failure('RESOURCE_LIMIT'),
      );
      for (var i = 0; i < 4; i++) await s.owner();
      expect(s.sessions.count, 8);
      final cap = await s.host.bindOwner(Object());
      await expectLater(s.sessions.openOwner(cap), failure('RESOURCE_LIMIT'));
      await s.close();
    },
  );
}
