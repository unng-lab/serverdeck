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
import '../../../serverdeck_windows/test/support/trusted_client_fixture.dart'
    show runOwnedFixtureLifecycle;

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
  final worker = await PipeWorker.openOperationalClient(
    name,
    currentUserSid(),
    root,
  );
  try {
    if (mode == 'normal' || mode == 'wrongtoken') {
      final bootstrap = OperationalBootstrapClient(
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
        if (command == 'pressure-write') {
          await session.peer.write([83]);
          stdout.writeln('PRESSURE_WROTE');
        }
        if (command == 'pressure-read') {
          var remaining = 1024 * 1024;
          while (remaining > 0) {
            final bytes = await session.peer.read(count: min(remaining, 65536));
            check(bytes.isNotEmpty && bytes.every((byte) => byte == 81));
            remaining -= bytes.length;
          }
          stdout.writeln('PRESSURE_READ');
        }
        if (command == 'repeat') {
          await fails(bootstrap.authenticate(), 'UNAUTHORIZED');
          stdout.writeln('REPEAT_REFUSED');
          break;
        }
      }
    } else {
      final peer = await worker.verifyOperationalPeer();
      final io = OperationalHandshakeIo(peer);
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
  final OperationalSessions registry;
  final String channel;
  final Duration Function()? clock;
  OperationalServerHandshake? handshake;
  OperationalPipePeer? peer;
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
    OperationalSessions registry, {
    String mode = 'normal',
    Duration Function()? clock,
    String? channelOverride,
  }) async {
    final name = pipeName();
    final server = await PipeWorker.createOperationalServer(
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
    peer = await server.verifyOperationalPeer();
    check(peer!.localRole == BundlePeerRole.locald);
    final auth = handshake = OperationalServerHandshake(
      peer: peer!,
      token: token,
      channel: channel,
      sessions: registry,
      elapsed: clock,
    );
    final io = OperationalHandshakeIo(peer!);
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

Future<void> controlPressure(Pair owner) async {
  final completions = <void Function()>[];
  final pending = <Future<void>>[];
  Future<T> track<T>(Future<T> work) {
    pending.add(work.then<void>((_) {}, onError: (Object _) {}));
    return work;
  }

  await runOwnedFixtureLifecycle(
    body: () async {
      final firstRequest = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        'session.ping',
      );
      completions.add(firstRequest.complete);
      final secondRequest = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        'session.ping',
      );
      completions.add(secondRequest.complete);
      final peer = owner.peer!;
      final observation = await peer.observeNextRevalidationForTest();
      var firstObservers = 0, secondObservers = 0;
      Future<void>? firstActual, secondActual;
      final firstProof = track(
        firstRequest.revalidate(
          observeNativeCompletion: (actual) {
            firstObservers++;
            firstActual = track(actual);
          },
        ),
      );
      var firstSettled = false;
      firstProof
          .then<void>(
            (_) => firstSettled = true,
            onError: (Object _) => firstSettled = true,
          )
          .ignore();
      // The reached command must retire before W and R consume native slots.
      await observation.reached.timeout(const Duration(seconds: 2));
      check(firstObservers == 1 && !firstSettled);
      var writeSettled = false, readSettled = false;
      final writing = track(peer.write(List<int>.filled(1024 * 1024, 81)));
      writing
          .then<void>(
            (_) => writeSettled = true,
            onError: (Object _) => writeSettled = true,
          )
          .ignore();
      final reading = track(peer.read(count: 1));
      reading
          .then<void>(
            (_) => readSettled = true,
            onError: (Object _) => readSettled = true,
          )
          .ignore();
      // Direct fourth-command refusal remains correct at physical W+V+R.
      await fails(owner.server.verifyOperationalPeer(), 'RESOURCE_LIMIT');
      final secondProof = track(
        secondRequest.revalidate(
          observeNativeCompletion: (actual) {
            secondObservers++;
            secondActual = track(actual);
          },
        ),
      );
      var secondSettled = false;
      secondProof
          .then<void>(
            (_) => secondSettled = true,
            onError: (Object _) => secondSettled = true,
          )
          .ignore();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      check(
        !firstSettled &&
            !secondSettled &&
            !writeSettled &&
            !readSettled &&
            secondObservers == 0,
      );
      owner.child.stdin.writeln('pressure-write');
      await owner.child.stdin.flush();
      check((await reading).single == 83);
      check(await owner.next() == 'PRESSURE_WROTE');
      // R has actually settled, so this ordinary release is not a fourth call.
      await observation.release();
      await firstProof;
      await secondProof;
      check(
        firstObservers == 1 &&
            secondObservers == 1 &&
            !identical(firstActual, secondActual),
      );
      await firstActual!;
      await secondActual!;
      owner.child.stdin.writeln('pressure-read');
      await owner.child.stdin.flush();
      await writing;
      check(await owner.next() == 'PRESSURE_READ');
      final healthy = await owner.registry.begin(
        owner.channel,
        owner.response!.sessionId,
        'session.ping',
      );
      healthy.complete();
    },
    cleanup: () async {
      for (final complete in completions) complete();
      // Exempt disconnect also releases the held proof if an assertion failed
      // before R settled; an ordinary observation release could hit quota3.
      await owner.peer!.disconnect();
      await Future.wait(pending);
    },
  );
}

Future<void> scenario(String root, String name) async {
  ownRoot(root);
  var time = Duration.zero, detached = 0, expired = 0;
  final registry = OperationalSessions(
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
    switch (name) {
      case 'control-pressure':
        final owner = await start('serverdeck.exe');
        await owner.exchange();
        check(await owner.next() == 'AUTH:owner');
        await controlPressure(owner);
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
        final held = <OperationalSessionRequest>[];
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
          final peer = await pair.server.verifyOperationalPeer();
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
