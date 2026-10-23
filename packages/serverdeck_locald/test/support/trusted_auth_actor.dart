import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';

const generation = '12345678-1234-4234-8234-123456789abc';
final token = List<int>.generate(32, (i) => i);
void check(bool value) {
  if (!value) throw StateError('FIXTURE_ASSERTION');
}

Future<void> finishClient(Process child) async {
  // A Windows Dart stdin subscription may retain the process after the command
  // loop exits. The fixture owner closes its writer before awaiting child exit.
  try {
    await child.stdin.close().timeout(const Duration(seconds: 2));
  } on IOException {
    /* Already exited/broken owned input pipe. */
  }
  await child.exitCode.timeout(const Duration(seconds: 10));
}

Future<void> fails(Future<Object?> action, String code) async {
  try {
    await action;
  } on StateError catch (error) {
    check(error.message == code);
    return;
  }
  throw StateError('EXPECTED_$code');
}

String pipeName() =>
    r'\\.\pipe\ServerDeckNext.v1.' +
    List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join() +
    '.0';
void ownRoot(String root) {
  check(
    p.isWithin(
      p.normalize(p.absolute(Directory.systemTemp.path)),
      p.normalize(p.absolute(root)),
    ),
  );
  check(p.basename(root).startsWith('serverdeck-mcp-bundle-'));
}

String sign(List<int> bytes) {
  final key = SecretKeyData(List<int>.of(token), overwriteWhenDestroyed: true);
  try {
    return base64Url
        .encode(
          DartHmac.sha256()
              .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
              .bytes,
        )
        .replaceAll('=', '');
  } finally {
    key.destroy();
  }
}

Future<void> client(List<String> args) async {
  final name = args[1], root = args[2], mode = args[3];
  ownRoot(root);
  final worker = await PipeWorker.openTrustedClient(
    name,
    currentUserSid(),
    root,
  );
  try {
    if (mode == 'normal' || mode == 'wrongtoken') {
      final bootstrap = TrustedBootstrapClient(
        pipe: worker,
        generation: generation,
        token: mode == 'wrongtoken' ? List<int>.filled(32, 9) : token,
      );
      final session = await bootstrap.authenticate();
      check(
        session.peer.localRole ==
            (session.role == OperationalRole.owner
                ? BundlePeerRole.owner
                : BundlePeerRole.mcp),
      );
      await session.revalidate();
      stdout.writeln('AUTH:${session.role.name}');
      await for (final command
          in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
        if (command == 'close') {
          await session.close();
          break;
        }
        if (command == 'verify') {
          try {
            await session.revalidate();
            stdout.writeln('VERIFIED');
          } on StateError catch (error) {
            stdout.writeln('ERROR:${error.message}');
          }
        }
        if (command == 'repeat') {
          await fails(bootstrap.authenticate(), 'UNAUTHORIZED');
          stdout.writeln('REPEAT_REFUSED');
          break;
        }
      }
    } else {
      final peer = await worker.verifyTrustedPeer();
      final io = TrustedHandshakeIo(peer);
      final watch = Stopwatch()..start();
      Duration remaining() => const Duration(seconds: 5) - watch.elapsed;
      final hello = OperationalHello.decode(await io.read(remaining));
      final nonce = base64Url
          .encode(List<int>.filled(32, 7))
          .replaceAll('=', '');
      final role = mode == 'wrongrole'
          ? OperationalRole.owner
          : hello.clientRole;
      final fakeHello = OperationalHello(
        generation: hello.generation,
        serverNonce: hello.serverNonce,
        buildId: hello.buildId,
        clientRole: role,
      );
      final transcript = OperationalBootstrapTranscript(
        hello: fakeHello,
        clientNonce: nonce,
        requestedCapabilities: [role.name],
      );
      final proof = mode == 'legacy'
          ? sign(
              utf8.encode(
                'client\n1\ndefault\n$generation\n${hello.serverNonce}\n$nonce\n${hello.buildId}\n${role.name}',
              ),
            )
          : sign(transcript.clientBytes());
      final request = OperationalAuthenticate(
        clientNonce: nonce,
        clientBuildId: mode == 'wrongbuild'
            ? hello.buildId.replaceFirst('Debug', 'Release')
            : hello.buildId,
        requestedCapabilities: [role.name],
        proof: proof,
      ).toJson();
      if (mode == 'extrarole')
        (request['authenticate'] as Map)['clientRole'] = 'owner';
      await io.write(request, remaining);
      stdout.writeln('SENT');
      await stdin.first;
    }
  } finally {
    await worker.close();
  }
}

final class Pair {
  Pair(
    this.server,
    this.child,
    this.lines,
    this.errors,
    this.registry,
    this.channel,
    this.clock,
  );
  final PipeWorker server;
  final Process child;
  final StreamIterator<String> lines;
  final Future<String> errors;
  final TrustedSessions registry;
  final String channel;
  final Duration Function()? clock;
  TrustedServerHandshake? handshake;
  TrustedPipePeer? peer;
  OperationalAuthenticated? response;
  List<int>? input;
  Future<String> next() async {
    check(await lines.moveNext().timeout(const Duration(seconds: 10)));
    check(lines.current.length < 256);
    return lines.current;
  }

  static Future<Pair> start(
    String root,
    String image,
    TrustedSessions registry, {
    String mode = 'normal',
    Duration Function()? clock,
    String? channelOverride,
    bool nativeGate = false,
  }) async {
    final name = pipeName();
    final server = await PipeWorker.createTrustedServer(
      name,
      currentUserSid(),
      root,
    );
    final accepting = server.accept();
    Process? child;
    try {
      child = await Process.start(p.join(root, image), [
        'client',
        name,
        root,
        mode,
      ]);
      final errors = child.stderr.transform(utf8.decoder).join();
      final lines = StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
      await accepting;
      if (nativeGate) {
        registry = await TrustedSessions.withNativePublicationGate(
          generation: generation,
          peer: await server.verifyTrustedPeer(),
          elapsed: clock,
        );
      }
      return Pair(
        server,
        child,
        lines,
        errors,
        registry,
        channelOverride ?? name,
        clock,
      );
    } catch (_) {
      child?.kill();
      if (child != null) await child.exitCode;
      await server.close();
      rethrow;
    }
  }

  Future<void> exchange({
    List<int>? replay,
    void Function()? beforeGrant,
    String? expectedError,
    bool badResponse = false,
    String? badHello,
    bool repeatHello = false,
    bool mutateInput = false,
    bool closeDuringGrant = false,
  }) async {
    peer = await server.verifyTrustedPeer();
    check(peer!.localRole == BundlePeerRole.locald);
    final auth = handshake = TrustedServerHandshake(
      peer: peer!,
      token: token,
      channel: channel,
      sessions: registry,
      elapsed: clock,
    );
    final io = TrustedHandshakeIo(peer!);
    final watch = Stopwatch()..start();
    Duration remaining() => const Duration(seconds: 5) - watch.elapsed;
    final hello = await auth.hello();
    final helloMessage = hello.toJson();
    if (badHello != null) {
      final body = helloMessage['hello'] as Map;
      if (badHello == 'role') body['clientRole'] = 'owner';
      if (badHello == 'build')
        body['buildId'] = hello.buildId.replaceFirst('Debug', 'Release');
      if (badHello == 'version') body['apiMinor'] = 0;
      if (badHello == 'generation')
        body['generation'] = '12345678-1234-4234-8234-123456789abd';
      await io.write(helloMessage, remaining);
      return;
    }
    await io.write(helloMessage, remaining);
    input = await io.read(remaining);
    if (repeatHello) {
      await fails(auth.hello(), 'UNAUTHORIZED');
      return;
    }
    beforeGrant?.call();
    if (expectedError != null) {
      final authenticating = auth.authenticate(replay ?? input!);
      if (closeDuringGrant) auth.close();
      await fails(authenticating, expectedError);
      return;
    }
    final authenticating = auth.authenticate(replay ?? input!);
    if (mutateInput) input!.fillRange(0, input!.length, 0);
    response = await authenticating;
    final message = response!.toJson();
    if (badResponse)
      (message['authenticated'] as Map)['proof'] = base64Url
          .encode(List<int>.filled(32, 0))
          .replaceAll('=', '');
    try {
      await io.write(message, remaining);
    } catch (_) {
      auth.close();
      rethrow;
    }
  }

  Future<void> close() async {
    handshake?.close();
    child.kill();
    await child.exitCode.timeout(const Duration(seconds: 10));
    await server.close();
    await lines.cancel();
    final error = await errors.timeout(const Duration(seconds: 5));
    check(error.isEmpty);
  }
}

Future<void> scenario(String root, String name) async {
  ownRoot(root);
  var time = Duration.zero, detached = 0, expired = 0;
  final registry = TrustedSessions(
    generation: generation,
    elapsed: () => time,
    onDetached: (_) => detached++,
    onExpiredChannel: (_) => expired++,
  );
  final pairs = <Pair>[];
  Future<Pair> start(
    String image, {
    String mode = 'normal',
    Duration Function()? clock,
  }) async {
    final pair = await Pair.start(
      root,
      image,
      registry,
      mode: mode,
      clock: clock,
    );
    pairs.add(pair);
    return pair;
  }

  try {
    if (name.startsWith('owner-connection')) {
      final owner = await start('serverdeck.exe');
      await owner.exchange();
      check(await owner.next() == 'AUTH:owner');
      final request = registry.reserve(
        owner.channel,
        owner.response!.sessionId,
        'servers.connect',
      );
      await fails(Future.sync(request.ownerConnectionContext), 'FORBIDDEN');
      time = const Duration(seconds: 4);
      await registry.completeAdmission(request);
      final context = request.ownerConnectionContext();
      check(identical(context, request.ownerConnectionContext()));
      check(
        context.belongsTo(registry) &&
            !context.belongsTo(TrustedSessions(generation: generation)) &&
            context.sessionId == request.sessionId &&
            context.generation == generation &&
            context.remaining == const Duration(seconds: 11),
      );
      request.complete();
      await fails(Future.sync(request.ownerConnectionContext), 'UNAUTHORIZED');
      if (name == 'owner-connection-physical') {
        final observation = await owner.peer!.observeNextRevalidationForTest();
        time = const Duration(milliseconds: 14900);
        final proof = context.revalidate();
        proof.ignore();
        try {
          await observation.reached.timeout(const Duration(seconds: 2));
          await fails(proof, 'TIMEOUT');
          var drained = false;
          final settling = context.settled.then<void>((_) {
            drained = true;
          });
          await Future<void>.delayed(const Duration(milliseconds: 20));
          check(!drained);
          await observation.release();
          await settling;
          check(drained);
          time = const Duration(seconds: 15);
          await fails(context.revalidate(), 'TIMEOUT');
        } finally {
          await observation.release();
          await context.settled;
        }
      } else if (name == 'owner-connection-detach' ||
          name == 'owner-connection-stop') {
        if (name == 'owner-connection-stop') {
          registry.stop();
        } else {
          owner.handshake!.close();
        }
        await context.detached;
        await fails(context.revalidate(), 'UNAUTHORIZED');
      } else if (name == 'owner-connection-native') {
        final manifest = File(p.join(root, 'foundation.manifest.json'));
        final original = manifest.readAsBytesSync();
        try {
          manifest.writeAsBytesSync([...original, 10]);
          await fails(context.revalidate(), 'UNAUTHORIZED');
          await context.detached;
          check(registry.count == 0);
        } finally {
          manifest.writeAsBytesSync(original);
        }
      } else {
        time = const Duration(seconds: 6);
        check(context.remaining == const Duration(seconds: 9));
        await context.revalidate();
        final wrong = await registry.begin(
          owner.channel,
          owner.response!.sessionId,
          'servers.trust.probe',
        );
        try {
          await fails(Future.sync(wrong.ownerConnectionContext), 'FORBIDDEN');
          check(context.matches(wrong));
        } finally {
          wrong.complete();
        }
        if (name == 'owner-connection-budget') {
          final late = await registry.begin(
            owner.channel,
            owner.response!.sessionId,
            'servers.connect',
          );
          try {
            time = const Duration(seconds: 11);
            await fails(Future.sync(late.ownerConnectionContext), 'TIMEOUT');
            time = const Duration(seconds: 15);
            await fails(context.revalidate(), 'TIMEOUT');
          } finally {
            late.complete();
          }
        } else {
          await fails(
            owner.peer!.observeNextRevalidationForTest(),
            'UNSUPPORTED',
          );
          final other = await start('serverdeck.exe');
          await other.exchange();
          check(await other.next() == 'AUTH:owner');
          final foreign = await registry.begin(
            other.channel,
            other.response!.sessionId,
            'servers.connect',
          );
          try {
            check(!context.matches(foreign));
          } finally {
            foreign.complete();
          }
          final mcp = await start('mcp.exe');
          await mcp.exchange();
          check(await mcp.next() == 'AUTH:mcp');
          final denied = await registry.begin(
            mcp.channel,
            mcp.response!.sessionId,
            'session.ping',
          );
          try {
            await fails(
              Future.sync(denied.ownerConnectionContext),
              'FORBIDDEN',
            );
            check(!context.matches(denied));
          } finally {
            denied.complete();
          }
        }
      }
      await context.settled;
      return;
    }
    if (name.startsWith('owner-context')) {
      final owner = await start('serverdeck.exe');
      await owner.exchange();
      check(await owner.next() == 'AUTH:owner');
      final request = registry.reserve(
        owner.channel,
        owner.response!.sessionId,
        'servers.trust.probe',
      );
      await fails(Future.sync(request.ownerProbeContext), 'FORBIDDEN');
      await registry.completeAdmission(request);
      final context = request.ownerProbeContext();
      check(identical(context, request.ownerProbeContext()));
      check(
        context.belongsTo(registry) &&
            context.sessionId == request.sessionId &&
            context.generation == generation,
      );
      request.complete();
      await fails(Future.sync(request.ownerProbeContext), 'UNAUTHORIZED');
      if (name == 'owner-context-physical') {
        final observation = await owner.peer!.observeNextRevalidationForTest();
        time = const Duration(milliseconds: 29900);
        final proof = context.revalidate();
        proof.ignore();
        try {
          await observation.reached.timeout(const Duration(seconds: 2));
          await fails(proof, 'TIMEOUT');
          var drained = false;
          final settling = context.settled.then<void>((_) {
            drained = true;
          });
          await Future<void>.delayed(const Duration(milliseconds: 20));
          check(!drained);
          await observation.release();
          await settling;
          check(drained);
          time = const Duration(seconds: 30);
          await fails(context.revalidate(), 'TIMEOUT');
        } finally {
          await observation.release();
          await context.settled;
        }
      } else if (name == 'owner-context-stop') {
        registry.stop();
        await context.detached;
        await fails(context.revalidate(), 'UNAUTHORIZED');
      } else if (name == 'owner-context-detach') {
        owner.handshake!.close();
        await context.detached;
        await fails(context.revalidate(), 'UNAUTHORIZED');
        final replacement = await Pair.start(
          root,
          'serverdeck.exe',
          registry,
          channelOverride: owner.channel,
        );
        pairs.add(replacement);
        await replacement.exchange();
        check(await replacement.next() == 'AUTH:owner');
        final fresh = await registry.begin(
          replacement.channel,
          replacement.response!.sessionId,
          'servers.trust.confirm',
        );
        try {
          check(!context.matches(fresh));
        } finally {
          fresh.complete();
        }
      } else if (name == 'owner-context-expiry') {
        time = const Duration(seconds: 60);
        await fails(context.revalidate(), 'UNAUTHORIZED');
        registry.expire();
        await context.detached;
      } else if (name == 'owner-context-native') {
        final manifest = File(p.join(root, 'foundation.manifest.json'));
        final original = manifest.readAsBytesSync();
        try {
          manifest.writeAsBytesSync([...original, 10]);
          await fails(context.revalidate(), 'UNAUTHORIZED');
          await context.detached;
          check(registry.count == 0);
        } finally {
          manifest.writeAsBytesSync(original);
        }
      } else {
        time = const Duration(seconds: 6);
        check(context.remaining == const Duration(seconds: 24));
        await context.revalidate();
        final fresh = await registry.begin(
          owner.channel,
          owner.response!.sessionId,
          'servers.trust.confirm',
        );
        try {
          check(context.matches(fresh));
          await fails(Future.sync(fresh.ownerProbeContext), 'FORBIDDEN');
          if (name == 'owner-context-budget') {
            time = const Duration(seconds: 30);
            await fails(context.revalidate(), 'TIMEOUT');
            // Challenge identity may outlive the probe's service deadline.
            final later = await registry.begin(
              owner.channel,
              owner.response!.sessionId,
              'servers.trust.confirm',
            );
            try {
              check(context.matches(later));
            } finally {
              later.complete();
            }
          } else {
            await fails(
              owner.peer!.observeNextRevalidationForTest(),
              'UNSUPPORTED',
            );
            final other = await start('serverdeck.exe');
            await other.exchange();
            check(await other.next() == 'AUTH:owner');
            final otherRequest = await registry.begin(
              other.channel,
              other.response!.sessionId,
              'servers.trust.confirm',
            );
            try {
              check(!context.matches(otherRequest));
            } finally {
              otherRequest.complete();
            }
            final mcp = await start('mcp.exe');
            await mcp.exchange();
            check(await mcp.next() == 'AUTH:mcp');
            final denied = await registry.begin(
              mcp.channel,
              mcp.response!.sessionId,
              'session.ping',
            );
            try {
              await fails(Future.sync(denied.ownerProbeContext), 'FORBIDDEN');
              check(!context.matches(denied));
            } finally {
              denied.complete();
            }
            final foreign = TrustedSessions(generation: generation);
            try {
              check(!context.belongsTo(foreign));
            } finally {
              await foreign.close();
            }
          }
        } finally {
          fresh.complete();
        }
      }
      await context.settled;
      return;
    }
    switch (name) {
      case 'native-gate':
        final owner = await Pair.start(
          root,
          'serverdeck.exe',
          registry,
          nativeGate: true,
        );
        pairs.add(owner);
        final gated = owner.registry;
        try {
          check(gated.hasNativePublicationGate);
          await owner.exchange();
          check(await owner.next() == 'AUTH:owner');
          final mcp = await Pair.start(root, 'mcp.exe', gated);
          pairs.add(mcp);
          await mcp.exchange();
          check(await mcp.next() == 'AUTH:mcp' && gated.count == 2);
          final request = await gated.begin(
            owner.channel,
            owner.response!.sessionId,
            'session.ping',
          );
          final foreign = TrustedSessions(generation: generation);
          try {
            await fails(foreign.completeAdmission(request), 'FORBIDDEN');
          } finally {
            await foreign.close();
          }
          await request.revalidate();
          request.complete();
          final entered = Completer<void>(), release = Completer<void>();
          final first = gated.runAuthorityMutation(() async {
            entered.complete();
            await release.future;
            return 7;
          });
          try {
            await entered.future;
            await fails(
              gated.runAuthorityMutation(
                () async => throw StateError('UNEXPECTED_EFFECT'),
                deadline: const Duration(milliseconds: 80),
              ),
              'TIMEOUT',
            );
          } finally {
            release.complete();
          }
          check(await first == 7);
          check(await gated.runAuthorityMutation(() async => 8) == 8);
          final lease = await gated.beginTargetChange();
          try {
            check(gated.targetChangesBlocked && gated.count == 1);
            await fails(
              gated.begin(mcp.channel, mcp.response!.sessionId, 'session.ping'),
              'UNAUTHORIZED',
            );
          } finally {
            await lease.close();
          }
          check(!gated.targetChangesBlocked);
        } finally {
          await gated.close();
        }
        check(!gated.hasNativePublicationGate && gated.count == 0);
        await fails(
          gated.runAuthorityMutation(() async => 9),
          'SERVICE_UNAVAILABLE',
        );
        break;
      case 'stale-close':
        final first = await start('mcp.exe');
        await first.exchange();
        check(await first.next() == 'AUTH:mcp');
        first.handshake!.close();
        final second = await Pair.start(
          root,
          'mcp.exe',
          registry,
          channelOverride: first.channel,
        );
        pairs.add(second);
        await second.exchange();
        check(await second.next() == 'AUTH:mcp');
        first.handshake!.close();
        check(registry.count == 1 && detached == 1);
        final rejected = await Pair.start(
          root,
          'mcp.exe',
          registry,
          mode: 'wrongrole',
          channelOverride: first.channel,
        );
        pairs.add(rejected);
        await rejected.exchange(expectedError: 'UNAUTHORIZED');
        await rejected.close();
        pairs.remove(rejected);
        check(registry.count == 1 && detached == 1);
        final request = await registry.begin(
          second.channel,
          second.response!.sessionId,
          'session.ping',
        );
        request.complete();
        break;
      case 'roles':
        for (final image in ['serverdeck.exe', 'mcp.exe']) {
          final pair = await start(image);
          await pair.exchange();
          final role = image == 'mcp.exe' ? 'mcp' : 'owner';
          check(await pair.next() == 'AUTH:$role');
          final method = role == 'mcp' ? 'session.ping' : 'grants.list';
          final request = await registry.begin(
            pair.channel,
            pair.response!.sessionId,
            method,
          );
          check(request.role.name == role);
          await request.revalidate();
          request.complete();
          request.complete();
          await fails(request.revalidate(), 'UNAUTHORIZED');
          for (final denied
              in role == 'mcp'
                  ? [
                      'grants.list',
                      'profiles.create',
                      'mcp.invoke',
                      'mcp.future',
                      'unknown',
                      'servers.trust.get',
                      'servers.trust.probe',
                      'servers.trust.probeStatus',
                      'servers.trust.probeCancel',
                      'servers.trust.confirm',
                      'servers.trust.revoke',
                    ]
                  : ['mcp.open']) {
            await fails(
              registry.begin(pair.channel, pair.response!.sessionId, denied),
              'FORBIDDEN',
            );
          }
          await fails(
            registry.begin(
              pair.channel,
              base64Url.encode(List<int>.filled(32, 9)).replaceAll('=', ''),
              method,
            ),
            'UNAUTHORIZED',
          );
          await fails(
            pair.handshake!.authenticate(pair.input!),
            'UNAUTHORIZED',
          );
          check(registry.count == 0);
          await pair.close();
          pairs.remove(pair);
        }
      case 'orphan':
        final pair = await start('mcp.exe');
        stdout.writeln('CHILD:${pair.child.pid}');
        await stdout.flush();
        await stdin.first;
      case 'proofs':
        List<int>? replay;
        final first = await start('mcp.exe');
        await first.exchange();
        check(await first.next() == 'AUTH:mcp');
        replay = first.input;
        await first.close();
        pairs.remove(first);
        for (final mode in [
          'replay',
          'wrongtoken',
          'wrongrole',
          'wrongbuild',
          'legacy',
          'extrarole',
        ]) {
          final pair = await start(
            'mcp.exe',
            mode: mode == 'replay' ? 'normal' : mode,
          );
          await pair.exchange(
            replay: mode == 'replay' ? replay : null,
            expectedError: mode == 'wrongbuild'
                ? 'INCOMPATIBLE'
                : 'UNAUTHORIZED',
          );
          check(registry.count == 0);
          // Normal client is waiting for a response after server refusal. Kill
          // the owned child before waiting; no forged failure response.
          await pair.close();
          pairs.remove(pair);
        }
      case 'quota':
        for (var i = 0; i < 4; i++) {
          final pair = await start('mcp.exe');
          await pair.exchange();
          check(await pair.next() == 'AUTH:mcp');
        }
        check(registry.count == 4 && registry.mcpCount == 4);
        final fifth = await start('mcp.exe');
        await fifth.exchange(expectedError: 'RESOURCE_LIMIT');
        await fifth.close();
        pairs.remove(fifth);
        for (var i = 0; i < 4; i++) {
          final pair = await start('serverdeck.exe');
          await pair.exchange();
          check(await pair.next() == 'AUTH:owner');
        }
        check(registry.count == 8 && registry.mcpCount == 4);
        final ninth = await start('serverdeck.exe');
        await ninth.exchange(expectedError: 'RESOURCE_LIMIT');
        await ninth.close();
        pairs.remove(ninth);
        final held = <TrustedSessionRequest>[];
        final pair = pairs.first;
        for (var i = 0; i < 16; i++)
          held.add(
            await registry.begin(
              pair.channel,
              pair.response!.sessionId,
              'session.ping',
            ),
          );
        await fails(
          registry.begin(
            pair.channel,
            pair.response!.sessionId,
            'session.ping',
          ),
          'RESOURCE_LIMIT',
        );
        for (final request in held) request.complete();
        (await registry.begin(
          pair.channel,
          pair.response!.sessionId,
          'session.ping',
        )).complete();
      case 'expiry':
        final pair = await start('mcp.exe');
        await pair.exchange();
        check(await pair.next() == 'AUTH:mcp');
        time = const Duration(seconds: 59);
        check(registry.count == 1);
        final request = await registry.begin(
          pair.channel,
          pair.response!.sessionId,
          'session.ping',
        );
        request.complete();
        time = const Duration(seconds: 119);
        registry.expire();
        registry.expire();
        check(registry.count == 0 && detached == 1 && expired == 1);
        await fails(
          registry.begin(
            pair.channel,
            pair.response!.sessionId,
            'session.ping',
          ),
          'UNAUTHORIZED',
        );
      case 'close':
        final pair = await start('mcp.exe');
        await pair.exchange(
          closeDuringGrant: true,
          expectedError: 'UNAUTHORIZED',
        );
        check(registry.count == 0);
        await pair.close();
        pairs.remove(pair);
        final live = await start('mcp.exe');
        await live.exchange();
        check(await live.next() == 'AUTH:mcp');
        final pending = registry.begin(
          live.channel,
          live.response!.sessionId,
          'session.ping',
        );
        registry.disconnect(live.channel);
        await fails(pending, 'UNAUTHORIZED');
        check(registry.count == 0);
      case 'snapshot':
        final pair = await start('mcp.exe');
        await pair.exchange(mutateInput: true);
        check(await pair.next() == 'AUTH:mcp');
        check(registry.count == 1);
      case 'deadline':
        var handshakeTime = Duration.zero;
        final pair = await start('mcp.exe', clock: () => handshakeTime);
        await pair.exchange(
          beforeGrant: () => handshakeTime = const Duration(seconds: 5),
          expectedError: 'TIMEOUT',
        );
        check(registry.count == 0);
      case 'client':
        for (final dimension in ['role', 'build', 'version', 'generation']) {
          final pair = await start('mcp.exe');
          try {
            await pair.exchange(badHello: dimension);
          } on StateError catch (error) {
            check(error.message == 'UNAUTHORIZED');
          }
          check(
            await pair.next() ==
                'ERROR:${dimension == 'role' ? 'UNAUTHORIZED' : 'INCOMPATIBLE'}',
          );
          check(registry.count == 0);
          await pair.close();
          pairs.remove(pair);
        }
        final invalid = await start('mcp.exe');
        try {
          await invalid.exchange(badResponse: true);
        } on StateError catch (error) {
          check(error.message == 'UNAUTHORIZED');
        }
        check(await invalid.next() == 'ERROR:UNAUTHORIZED');
        await finishClient(invalid.child);
        // Peer loss is checked by the normal request gate, not a synthetic
        // protocol assertion or an owner-selected role string.
        if (invalid.response != null && registry.count != 0) {
          await fails(
            registry.begin(
              invalid.channel,
              invalid.response!.sessionId,
              'session.ping',
            ),
            'UNAUTHORIZED',
          );
        }
        check(registry.count == 0);
        await invalid.close();
        pairs.remove(invalid);
        final repeated = await start('mcp.exe');
        await repeated.exchange();
        check(await repeated.next() == 'AUTH:mcp');
        repeated.child.stdin.writeln('repeat');
        await repeated.child.stdin.flush();
        check(await repeated.next() == 'REPEAT_REFUSED');
        await finishClient(repeated.child);
        await fails(
          registry.begin(
            repeated.channel,
            repeated.response!.sessionId,
            'session.ping',
          ),
          'UNAUTHORIZED',
        );
        check(registry.count == 0);
      case 'framing':
        for (final frame in <List<int>>[
          [0, 0, 0, 0],
          [1, 32, 0, 0],
          frameBytes([255]),
          frameBytes(utf8.encode('{"hello":{},"hello":{}}')),
        ]) {
          final pair = await start('mcp.exe');
          final peer = await pair.server.verifyTrustedPeer();
          try {
            await peer.write(frame);
          } on StateError catch (error) {
            check(error.message == 'UNAUTHORIZED');
          }
          check(await pair.next() == 'ERROR:UNAUTHORIZED');
          check(registry.count == 0);
          await pair.close();
          pairs.remove(pair);
        }
      case 'tamper':
        final pair = await start('mcp.exe');
        final path = p.join(root, 'foundation.manifest.json');
        final original = File(path).readAsBytesSync();
        try {
          await pair.exchange(
            beforeGrant: () => File(path).writeAsBytesSync([...original, 10]),
            expectedError: 'UNAUTHORIZED',
          );
          check(registry.count == 0);
        } finally {
          File(path).writeAsBytesSync(original);
        }
        await fails(pair.peer!.revalidate(), 'UNAUTHORIZED');
      default:
        throw StateError('UNKNOWN_SCENARIO');
    }
  } finally {
    registry.stop();
    for (final pair in pairs.reversed) await pair.close();
  }
}

Future<void> main(List<String> args) async {
  try {
    if (args[0] == 'client') {
      await client(args);
    } else {
      containCurrentFixtureTree();
      await scenario(args[1], args[2]);
      stdout.writeln('PASS:${args[2]}');
    }
  } on StateError catch (error) {
    if (args[0] == 'client')
      stdout.writeln('ERROR:${error.message}');
    else {
      stderr.writeln(error);
      exitCode = 1;
    }
  } catch (error, trace) {
    stderr.writeln(error);
    stderr.writeln(trace);
    exitCode = 1;
  }
}
