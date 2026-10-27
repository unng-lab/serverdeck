import 'dart:math';
import 'dart:io';

import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

String newHash() => List.generate(
  32,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

void main() {
  test(
    'idle accept and bidirectional reads survive retiring VM threads',
    () async {
      final sid = currentUserSid();
      final name = '\\\\.\\pipe\\ServerDeckNext.v1.${newHash()}.0';
      final server = await PipeWorker.createServer(name, sid);
      PipeWorker? client;
      try {
        var acceptFinished = false;
        final accepted = server.accept().whenComplete(
          () => acceptFinished = true,
        );
        accepted.ignore();
        await Future<void>.delayed(const Duration(seconds: 8));
        expect(acceptFinished, false);
        client = await PipeWorker.openClient(name, sid);
        await accepted.timeout(const Duration(seconds: 5));
        var serverFinished = false, clientFinished = false;
        final serverRead = server
            .read(deadline: const Duration(seconds: 20))
            .whenComplete(() => serverFinished = true);
        final clientRead = client
            .read(deadline: const Duration(seconds: 20))
            .whenComplete(() => clientFinished = true);
        serverRead.ignore();
        clientRead.ignore();
        await Future<void>.delayed(const Duration(seconds: 8));
        expect(serverFinished, false);
        expect(clientFinished, false);
        await Future.wait([
          client.write([1, 2]),
          server.write([3, 4]),
        ]);
        expect(await serverRead.timeout(const Duration(seconds: 5)), [1, 2]);
        expect(await clientRead.timeout(const Duration(seconds: 5)), [3, 4]);
      } finally {
        await client?.close();
        await server.close();
      }
    },
    testOn: 'windows',
    timeout: const Timeout(Duration(seconds: 45)),
  );
  test('eight distinct worker-owned slots exchange and cancel without blocking caller', () async {
    final sid = currentUserSid();
    final pool = await PipeServerPool.create(newHash(), sid);
    PipeWorker? client;
    final self = RetainedProcessIdentity.open(pid);
    try {
      expect(pool.names.toSet().length, 8);
      final server = pool.slots[7];
      final accepted = server.accept(deadline: const Duration(seconds: 5));
      client = await PipeWorker.openClient(pool.names[7], sid);
      await accepted;
      await client.verifyPeer(sid, self.imagePath, fileSha256(self.imagePath));
      final read = server.read();
      await client.write([4, 2]);
      expect(await read, [4, 2]);
      final pending = expectLater(server.read(), throwsStateError);
      await Future.wait([server.close(), server.close()]);
      await pending;
      await expectLater(server.read(), throwsStateError);
    } finally {
      self.close();
      await client?.close();
      await pool.close();
    }
  }, testOn: 'windows');
  test('slot collision rolls back only newly acquired slots', () async {
    final sid = currentUserSid(), hash = newHash();
    final name = '\\\\.\\pipe\\ServerDeckNext.v1.$hash.4';
    final foreign = await PipeWorker.createServer(name, sid);
    try {
      await expectLater(PipeServerPool.create(hash, sid), throwsStateError);
      final earlier = await PipeWorker.createServer(
        '\\\\.\\pipe\\ServerDeckNext.v1.$hash.0',
        sid,
      );
      await earlier.close();
      final accepted = foreign.accept(deadline: const Duration(seconds: 5));
      final client = await PipeWorker.openClient(name, sid);
      await accepted;
      await client.close();
    } finally {
      await foreign.close();
    }
  }, testOn: 'windows');
}
