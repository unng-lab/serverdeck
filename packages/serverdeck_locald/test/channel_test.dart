import 'dart:async';
import 'dart:typed_data';

import 'package:serverdeck_locald/api/auth.dart';
import 'package:serverdeck_locald/api/channel.dart';
import 'package:serverdeck_locald/api/server.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

import 'auth_test.dart' as auth;

class MemoryPipe {
  final input = StreamController<List<int>>();
  final output = StreamController<List<int>>();
  late final reader = StreamIterator(input.stream);
  late final replies = StreamIterator(output.stream);
  List<int> buffered = [];
  final deadlines = <Duration>[];
  final readCounts = <int>[];
  int disconnects = 0;
  bool closed = false;
  Future<void> Function()? beforeWrite;
  Future<Uint8List> read(int count, Duration deadline) async {
    deadlines.add(deadline);
    readCounts.add(count);
    if (buffered.isEmpty) {
      if (!await reader.moveNext().timeout(deadline)) return Uint8List(0);
      buffered = List.of(reader.current);
    }
    final size = count < buffered.length ? count : buffered.length;
    final result = Uint8List.fromList(buffered.take(size).toList());
    buffered = buffered.skip(size).toList();
    return result;
  }

  Future<void> write(List<int> bytes, Duration deadline) async {
    await beforeWrite?.call();
    if (closed) throw StateError('SERVICE_UNAVAILABLE');
    output.add(List.of(bytes));
  }

  Future<void> disconnect() async {
    if (closed) return;
    closed = true;
    disconnects++;
    unawaited(input.close());
    unawaited(output.close());
  }

  void send(List<int> payload) => input.add(frameBytes(payload));
  Future<Map<String, Object?>> response() async {
    expect(
      await replies.moveNext().timeout(const Duration(seconds: 3)),
      isTrue,
    );
    return StrictCodec().decode(
      FrameDecoder(maxBytes: 8 * 1024 * 1024).add(replies.current).single,
    );
  }

  Future<void> dispose() async {
    await disconnect();
    await reader.cancel();
    await replies.cancel();
  }
}

class Harness {
  Harness({Duration Function()? elapsed}) {
    sessions = SessionRegistry(generation: auth.generation);
    handshake = ServerHandshake(
      token: auth.token,
      generation: auth.generation,
      buildId: auth.buildId,
      channel: 'owned-unit',
      sessions: sessions,
      verifyPeer: () async {
        peerChecks++;
      },
    );
    server = ApiServer(
      sessions: sessions,
      readiness: () => const ReadinessView(
        state: ReadinessState.starting,
        reason: null,
        workspaceId: null,
        generation: auth.generation,
      ),
      coordinator: () => null,
    );
    channel = ServerChannel(
      handshake: handshake,
      server: server,
      read: pipe.read,
      write: pipe.write,
      drainOutput: (_) async {},
      disconnect: pipe.disconnect,
      elapsed: elapsed,
    );
  }
  final pipe = MemoryPipe();
  late final SessionRegistry sessions;
  late final ServerHandshake handshake;
  late final ApiServer server;
  late final ServerChannel channel;
  int peerChecks = 0;
  Future<String> authenticate() async {
    final hello = (await pipe.response())['hello'] as Map;
    pipe.send(
      await auth.frame(
        ServerHello(
          generation: auth.generation,
          serverNonce: hello['serverNonce'] as String,
        ),
        ['profiles.read', 'readiness.read'],
      ),
    );
    final grant = (await pipe.response())['authenticated'] as Map;
    return grant['sessionId'] as String;
  }

  void request(String session, String method) => pipe.send(
    StrictCodec().encode(
      ApiRequest(
        id: auth.generation,
        sessionId: session,
        method: method,
        params: const {},
      ).toJson(),
    ),
  );
  Future<void> dispose() async {
    await channel.close();
    sessions.stop();
    await pipe.dispose();
  }
}

void main() {
  test(
    'backpressure bounds pending replies and external close cancels idle read',
    () async {
      final h = Harness();
      final running = h.channel.run();
      running.ignore();
      final blocked = Completer<void>(), release = Completer<void>();
      try {
        final session = await h.authenticate();
        h.pipe.beforeWrite = () async {
          if (!blocked.isCompleted) blocked.complete();
          await release.future;
        };
        final before = h.pipe.deadlines.length;
        final payload = StrictCodec().encode(
          ApiRequest(
            id: auth.generation,
            sessionId: session,
            method: 'session.ping',
            params: const {},
          ).toJson(),
        );
        h.pipe.input.add([for (var i = 0; i < 20; i++) ...frameBytes(payload)]);
        await blocked.future;
        // Flush the finite microtask chain without a timing-dependent sleep.
        for (var i = 0; i < 200; i++) {
          await Future<void>.value();
        }
        expect(h.pipe.deadlines.length - before, inInclusiveRange(31, 32));
        expect(h.pipe.buffered.length, 4 * (payload.length + 4));
        await h.channel.close();
        expect(h.sessions.count, 0);
        release.complete();
        await running;
        expect(await h.pipe.replies.moveNext(), false);
        expect(h.pipe.disconnects, 1);
      } finally {
        if (!release.isCompleted) release.complete();
        await h.dispose();
      }
    },
  );
  test(
    'bad proof and oversized length revoke without a grant or echo',
    () async {
      for (final oversized in [false, true]) {
        final h = Harness();
        final running = h.channel.run();
        running.ignore();
        try {
          final hello = (await h.pipe.response())['hello'] as Map;
          if (oversized) {
            final header = Uint8List(4);
            ByteData.sublistView(header).setUint32(0, 8193, Endian.little);
            h.pipe.input.add(header);
          } else {
            h.pipe.send(
              await auth.frame(
                ServerHello(
                  generation: auth.generation,
                  serverNonce: hello['serverNonce'] as String,
                ),
                ['readiness.read'],
                digest: auth.clientNonce,
              ),
            );
          }
          await running;
          expect(h.sessions.count, 0);
          expect(await h.pipe.replies.moveNext(), false);
          expect(h.peerChecks, 1);
        } finally {
          await h.dispose();
        }
      }
    },
  );
  test(
    'wire handshake precedes requests, close reply precedes native disconnect',
    () async {
      final h = Harness();
      final running = h.channel.run();
      running.ignore();
      try {
        final session = await h.authenticate();
        expect(h.peerChecks, 2);
        h.request(session, 'readiness.get');
        expect(
          ((await h.pipe.response())['result'] as Map)['state'],
          'starting',
        );
        h.request(session, 'profiles.list');
        expect(
          ((await h.pipe.response())['error'] as Map)['code'],
          'NOT_READY',
        );
        h.request(session, 'session.close');
        expect(((await h.pipe.response())['result'] as Map)['closed'], true);
        await running;
        expect(h.sessions.count, 0);
        expect(h.pipe.disconnects, 1);
        await h.channel.close();
        expect(h.pipe.disconnects, 1);
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'invalid authenticated frame closes without private input echo',
    () async {
      final h = Harness();
      final running = h.channel.run();
      running.ignore();
      try {
        await h.authenticate();
        h.pipe.send([0xff, ...'private-input'.codeUnits]);
        await running;
        expect(h.sessions.count, 0);
        expect(await h.pipe.replies.moveNext(), isFalse);
        expect(h.pipe.disconnects, 1);
      } finally {
        await h.dispose();
      }
    },
  );
  test(
    'absolute partial deadline is not refreshed by fragmented bytes',
    () async {
      var now = Duration.zero;
      final h = Harness(elapsed: () => now);
      final running = h.channel.run();
      running.ignore();
      try {
        await h.authenticate();
        h.pipe.input.add([1]);
        final wait = Stopwatch()..start();
        while (h.pipe.readCounts.last != 3) {
          if (wait.elapsed > const Duration(seconds: 3))
            throw StateError('PARTIAL_READ_NOT_OBSERVED');
          await Future<void>.delayed(Duration.zero);
        }
        now = const Duration(seconds: 6);
        h.pipe.input.add([0]);
        await running;
        expect(h.pipe.disconnects, 1);
        expect(h.sessions.count, 0);
      } finally {
        await h.dispose();
      }
    },
  );
}
