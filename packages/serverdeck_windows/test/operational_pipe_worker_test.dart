import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'mcp_build_bundle_test.dart' as b;

String pipeName() =>
    r'\\.\pipe\ServerDeckNext.v1.' +
    List.generate(
      32,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join() +
    '.7';
final buildId = '${'a' * 40}+Debug+${'b' * 64}';

class Actor {
  Actor(this.child, this.lines);
  final Process child;
  final StreamIterator<String> lines;
  static Future<Actor> start(
    b.Fixture fixture,
    String executable,
    String kind,
    String name,
  ) async {
    final child = await Process.start(executable, [kind, name, fixture.path]);
    fixture.children.add(child);
    fixture.errors.add(b.boundedOutput(child.stderr));
    final actor = Actor(
      child,
      StreamIterator(
        child.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      ),
    );
    return actor;
  }

  Future<String> next() async {
    expect(await lines.moveNext().timeout(const Duration(seconds: 12)), isTrue);
    expect(lines.current.length, lessThanOrEqualTo(256));
    return lines.current;
  }

  Future<String> command(String value) async {
    child.stdin.writeln(value);
    await child.stdin.flush();
    return next();
  }
}

void main() {
  test('legacy worker cannot issue an operational peer handle', () async {
    final worker = await PipeWorker.createServer(pipeName(), currentUserSid());
    try {
      await expectLater(worker.verifyOperationalPeer(), b.code('UNAUTHORIZED'));
    } finally {
      await worker.close();
    }
  }, testOn: 'windows');

  group(
    'actual operational pipe roles',
    () {
      late Directory compiledRoot;
      late String compiled;
      late b.Fixture fixture;
      final actors = <Actor>[];
      setUpAll(() async {
        compiledRoot = Directory.systemTemp.createTempSync(
          'serverdeck-mcp-bundle-pipe-',
        );
        b.ownRoot(compiledRoot.path);
        compiled = p.join(compiledRoot.path, 'actor.exe');
        await b.compilePeer(
          compiled,
          source: 'test/support/operational_pipe_actor.dart',
        );
      });
      tearDownAll(() {
        b.ownRoot(compiledRoot.path);
        compiledRoot.deleteSync(recursive: true);
      });
      setUp(() {
        fixture = b.Fixture(compiled);
      });
      tearDown(() async {
        await fixture.close();
        for (final actor in actors) await actor.lines.cancel();
        actors.clear();
      });
      Future<Actor> start(
        String image,
        String kind,
        String name, {
        String? path,
      }) async {
        final actor = await Actor.start(
          fixture,
          path ?? p.join(fixture.path, image),
          kind,
          name,
        );
        actors.add(actor);
        return actor;
      }

      Future<void> echo(Actor server, Actor client) async {
        expect(await client.command('write'), 'WROTE');
        expect(await server.command('read'), 'DATA:42');
        expect(await server.command('write'), 'WROTE');
        expect(await client.command('read'), 'DATA:43');
        expect(await server.command('drain'), 'DRAINED');
      }

      Future<Actor> connect(
        Actor server,
        String image,
        String name,
        String role,
      ) async {
        final accepting = server.command('accept');
        final client = await start(image, 'client', name);
        expect(await client.next(), 'READY');
        expect(await accepting, 'ACCEPTED');
        expect(await client.command('verify'), 'ROLE:locald:$buildId');
        expect(await server.command('verify'), 'ROLE:$role:$buildId');
        return client;
      }

      test(
        'owner to mcp physical reconnect rejects raw and old epoch IO',
        () async {
          final name = pipeName();
          final host = await start('locald.exe', 'server', name);
          expect(await host.next(), 'READY');
          expect(await host.command('raw'), 'RAW_DENIED');
          final owner = await connect(host, 'serverdeck.exe', name, 'owner');
          expect(await host.command('raw'), 'RAW_DENIED');
          await echo(host, owner);
          expect(await host.command('disconnect'), 'DISCONNECTED');
          expect(await owner.command('close'), 'CLOSED');
          final mcp = await connect(host, 'mcp.exe', name, 'mcp');
          expect(await host.command('old'), 'STALE_DENIED');
          await echo(host, mcp);
          expect(await host.command('disconnect'), 'DISCONNECTED');
          expect(await mcp.command('close'), 'CLOSED');
          expect(await host.command('close'), 'CLOSED');
        },
      );

      test(
        'manifest restore and repeated accept cannot clear failed binding',
        () async {
          final name = pipeName();
          final host = await start('locald.exe', 'server', name);
          expect(await host.next(), 'READY');
          final owner = await connect(host, 'serverdeck.exe', name, 'owner');
          fixture.write('${jsonEncode(fixture.document)} ');
          expect(await host.command('verify'), 'ERR:UNAUTHORIZED');
          fixture.write();
          expect(await host.command('accept'), 'ERR:SERVICE_UNAVAILABLE');
          expect(await host.command('verify'), 'ERR:UNAUTHORIZED');
          expect(await host.command('old'), 'STALE_DENIED');
          expect(await host.command('disconnect'), 'DISCONNECTED');
          expect(await owner.command('close'), 'CLOSED');
          final mcp = await connect(host, 'mcp.exe', name, 'mcp');
          await echo(host, mcp);
          expect(await host.command('disconnect'), 'DISCONNECTED');
          expect(await mcp.command('close'), 'CLOSED');
          expect(await host.command('close'), 'CLOSED');
        },
      );

      test(
        'concurrent accept and cancelled read cannot reopen an old slot',
        () async {
          final name = pipeName();
          final server = await start('locald.exe', 'server', name);
          expect(await server.next(), 'READY');
          expect(await server.command('listen'), 'LISTENING');
          expect(await server.command('accept'), 'ERR:SERVICE_UNAVAILABLE');
          expect(await server.command('disconnect'), 'DISCONNECTED');
          expect(
            await server.command('accept-result'),
            'RESULT:SERVICE_UNAVAILABLE',
          );
          final owner = await connect(server, 'serverdeck.exe', name, 'owner');
          expect(await server.command('pending'), 'PENDING');
          expect(await server.command('disconnect'), 'DISCONNECTED');
          expect(
            await server.command('pending-result'),
            'RESULT:SERVICE_UNAVAILABLE',
          );
          expect(await owner.command('close'), 'CLOSED');
          final mcp = await connect(server, 'mcp.exe', name, 'mcp');
          expect(await server.command('old'), 'STALE_DENIED');
          await echo(server, mcp);
          expect(await server.command('disconnect'), 'DISCONNECTED');
          expect(await mcp.command('close'), 'CLOSED');
          expect(await server.command('close'), 'CLOSED');
        },
      );

      test('native timeout latches IO until confirmed disconnect', () async {
        final name = pipeName();
        final host = await start('locald.exe', 'server', name);
        expect(await host.next(), 'READY');
        final owner = await connect(host, 'serverdeck.exe', name, 'owner');
        expect(await host.command('timeout'), 'ERR:TIMEOUT');
        expect(await host.command('verify'), 'ERR:UNAUTHORIZED');
        expect(await host.command('accept'), 'ERR:SERVICE_UNAVAILABLE');
        expect(await host.command('disconnect'), 'DISCONNECTED');
        expect(await owner.command('close'), 'CLOSED');
        expect(await host.command('close'), 'CLOSED');
      });

      test('manifest change during a real pending read suppresses returned bytes', () async {
        final name = pipeName();
        final server = await start('locald.exe', 'server', name);
        expect(await server.next(), 'READY');
        final accepting = server.command('accept');
        final client = await start('serverdeck.exe', 'legacy-client', name);
        expect(await client.next(), 'READY');
        expect(await accepting, 'ACCEPTED');
        expect(await server.command('verify'), 'ROLE:owner:$buildId');
        expect(await server.command('pending'), 'PENDING');
        // Ordered worker messages: this successful check runs after the read's
        // pre-IO guard has finished and the actual native read has been started.
        expect(await server.command('verify'), 'ROLE:owner:$buildId');
        fixture.write('${jsonEncode(fixture.document)} ');
        expect(await client.command('write'), 'WROTE');
        expect(await server.command('pending-result'), 'RESULT:UNAUTHORIZED');
        fixture.write();
        expect(await server.command('verify'), 'ERR:UNAUTHORIZED');
        expect(await server.command('accept'), 'ERR:SERVICE_UNAVAILABLE');
        expect(await server.command('disconnect'), 'DISCONNECTED');
        expect(await client.command('close'), 'CLOSED');
        expect(await server.command('close'), 'CLOSED');
      });

      test('operational full read write drain cancellation preserves slot reuse', () async {
        final name = pipeName();
        final server = await start('locald.exe', 'server', name);
        expect(await server.next(), 'READY');
        final owner = await connect(server, 'serverdeck.exe', name, 'owner');
        expect(await server.command('full'), 'FULL_PENDING');
        expect(await server.command('disconnect'), 'DISCONNECTED');
        expect(
          await server.command('full-result'),
          'RESULT:SERVICE_UNAVAILABLE,SERVICE_UNAVAILABLE,SERVICE_UNAVAILABLE',
        );
        expect(await owner.command('close'), 'CLOSED');
        final mcp = await connect(server, 'mcp.exe', name, 'mcp');
        expect(await server.command('old'), 'STALE_DENIED');
        await echo(server, mcp);
        expect(await server.command('disconnect'), 'DISCONNECTED');
        expect(await mcp.command('close'), 'CLOSED');
        expect(await server.command('close'), 'CLOSED');
      });

      test('actual kernel peer role refuses legacy wrong-direction and unknown images', () async {
        final fakeName = pipeName();
        final fake = await start('serverdeck.exe', 'legacy-server', fakeName);
        expect(await fake.next(), 'READY');
        final accepting = fake.command('accept');
        final client = await start('mcp.exe', 'client', fakeName);
        expect(await client.next(), 'READY');
        expect(await accepting, 'ACCEPTED');
        expect(await client.command('verify'), 'ERR:UNAUTHORIZED');
        expect(await client.command('verify'), 'ERR:UNAUTHORIZED');
        expect(await fake.command('disconnect'), 'DISCONNECTED');
        expect(await client.command('close'), 'CLOSED');
        expect(await fake.command('close'), 'CLOSED');

        final name = pipeName();
        final server = await start('locald.exe', 'server', name);
        expect(await server.next(), 'READY');
        final stranger = File(compiled)
            .copySync(p.join(fixture.path, 'stranger.exe'));
        final outside = File(compiled)
            .copySync(p.join(compiledRoot.path, 'serverdeck.exe'));
        for (final path in [
          p.join(fixture.path, 'locald.exe'),
          stranger.path,
          outside.path,
        ]) {
          final accepting = server.command('accept');
          final bad = await start('unused', 'legacy-client', name, path: path);
          expect(await bad.next(), 'READY');
          expect(await accepting, 'ACCEPTED');
          expect(await server.command('verify'), 'ERR:UNAUTHORIZED');
          expect(await server.command('accept'), 'ERR:SERVICE_UNAVAILABLE');
          expect(await server.command('disconnect'), 'DISCONNECTED');
          expect(await bad.command('close'), 'CLOSED');
        }
        final mcp = await connect(server, 'mcp.exe', name, 'mcp');
        await echo(server, mcp);
        expect(await server.command('disconnect'), 'DISCONNECTED');
        expect(await mcp.command('close'), 'CLOSED');
        expect(await server.command('close'), 'CLOSED');
      });

      test(
        'startup verifies own image and bundle before opening a pipe',
        () async {
          final name = pipeName();
          for (final entry in [
            ('serverdeck.exe', 'server'),
            ('mcp.exe', 'server'),
            ('locald.exe', 'client'),
          ]) {
            final actor = await start(entry.$1, entry.$2, name);
            expect(await actor.next(), 'STARTUP_ERR:UNAUTHORIZED');
            expect(
              await actor.child.exitCode.timeout(const Duration(seconds: 5)),
              0,
            );
          }
          final outside = File(compiled)
              .copySync(p.join(compiledRoot.path, 'serverdeck.exe'));
          final actor = await start(
            'serverdeck.exe',
            'client',
            name,
            path: outside.path,
          );
          expect(await actor.next(), 'STARTUP_ERR:UNAUTHORIZED');
          fixture.write('{}');
          final malformed = await start('locald.exe', 'server', name);
          expect(await malformed.next(), 'STARTUP_ERR:INCOMPATIBLE');
          fixture.write();
          final host = await start('locald.exe', 'server', name);
          expect(await host.next(), 'READY');
          final owner = await connect(host, 'serverdeck.exe', name, 'owner');
          await echo(host, owner);
          expect(await host.command('disconnect'), 'DISCONNECTED');
          expect(await owner.command('close'), 'CLOSED');
          expect(await host.command('close'), 'CLOSED');
        },
      );
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 150)),
  );
}
