import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/security.dart';

Future<void> denied(Future<Object?> Function() run) async {
  try {
    await run();
  } on StateError catch (e) {
    if (e.message == 'UNAUTHORIZED') return;
    rethrow;
  }
  throw StateError('EXPECTED_UNAUTHORIZED');
}

Future<void> main(List<String> args) async {
  final server = args[0].endsWith('server'),
      legacy = args[0].startsWith('legacy-'),
      operational = args[0].startsWith('operational-'),
      name = args[1],
      root = args[2];
  PipeWorker worker;
  try {
    worker = legacy
        ? (server
              ? await PipeWorker.createServer(name, currentUserSid())
              : await PipeWorker.openClient(name, currentUserSid()))
        : operational
        ? (server
              ? await PipeWorker.createOperationalServer(
                  name,
                  currentUserSid(),
                  root,
                )
              : await PipeWorker.openOperationalClient(
                  name,
                  currentUserSid(),
                  root,
                ))
        : server
        ? await PipeWorker.createTrustedServer(name, currentUserSid(), root)
        : await PipeWorker.openTrustedClient(name, currentUserSid(), root);
  } on StateError catch (e) {
    stdout.writeln('STARTUP_ERR:${e.message}');
    return;
  }
  TrustedPipePeer? peer, original;
  OperationalPublicationGate? gate;
  OperationalPublicationLease? lease;
  Future<String>? pendingRead, pendingAccept, pendingWrite, pendingDrain;
  Future<String> result(Future<Object?> operation) async {
    try {
      await operation;
      return 'OK';
    } on StateError catch (e) {
      return e.message.toString();
    }
  }

  stdout.writeln('READY');
  await stdout.flush();
  try {
    await for (final command
        in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
      try {
        switch (command) {
          case 'bootstrap-denied':
            final bootstrap = TrustedBootstrapClient(
              pipe: worker,
              generation: '10000000-0000-4000-8000-000000000001',
              token: List<int>.filled(32, 0),
            );
            await denied(bootstrap.authenticate);
            stdout.writeln('BOOTSTRAP_DENIED');
          case 'wrong-peer':
            await denied(() => worker.verifyOperationalPeer());
            stdout.writeln('WRONG_PEER_DENIED');
          case 'trusted-denied':
            await denied(() => worker.verifyTrustedPeer());
            stdout.writeln('TRUSTED_DENIED');
          case 'verify-operational':
            final old = await worker.verifyOperationalPeer();
            stdout.writeln('OPERATIONAL:${old.role.name}');
          case 'gate':
            gate = await peer!.publicationGate(
              '10000000-0000-4000-8000-000000000001',
            );
            stdout.writeln('GATE:${gate.localRole.name}');
          case 'gate-acquire':
            lease = await gate!.acquire();
            stdout.writeln('GATE_ACQUIRED');
          case 'gate-timeout':
            try {
              final unexpected = await gate!.acquire(
                deadline: const Duration(milliseconds: 40),
              );
              await unexpected.close();
              throw StateError('EXPECTED_GATE_TIMEOUT');
            } on StateError catch (error) {
              if (error.message != 'TIMEOUT') rethrow;
            }
            stdout.writeln('GATE_TIMEOUT');
          case 'gate-release':
            await lease!.close();
            lease = null;
            stdout.writeln('GATE_RELEASED');
          case 'gate-close':
            await gate!.close();
            gate = null;
            stdout.writeln('GATE_CLOSED');
          case 'accept':
            await worker.accept(deadline: const Duration(seconds: 3));
            stdout.writeln('ACCEPTED');
          case 'listen':
            pendingAccept = result(
              worker.accept(deadline: const Duration(seconds: 3)),
            );
            stdout.writeln('LISTENING');
          case 'accept-result':
            stdout.writeln('RESULT:${await pendingAccept!}');
          case 'verify':
            peer = await worker.verifyTrustedPeer();
            original ??= peer;
            stdout.writeln('ROLE:${peer.role.name}:${peer.buildId}');
          case 'raw':
            await denied(() => worker.read(count: 1));
            await denied(() => worker.write([99]));
            await denied(() => worker.drainOutput());
            await denied(
              () => worker.verifyPeer(currentUserSid(), 'claimed', '0' * 64),
            );
            stdout.writeln('RAW_DENIED');
          case 'old':
            await denied(() => original!.revalidate());
            await denied(() => original!.read(count: 1));
            await denied(() => original!.write([99]));
            await denied(() => original!.drainOutput());
            stdout.writeln('STALE_DENIED');
          case 'old-disconnect':
            await denied(() => original!.disconnect());
            stdout.writeln('STALE_DISCONNECT_DENIED');
          case 'write':
            if (legacy) {
              await worker.write([server ? 43 : 42]);
            } else {
              await peer!.write([server ? 43 : 42]);
            }
            stdout.writeln('WROTE');
          case 'read':
            final bytes = await peer!.read(count: 1);
            stdout.writeln('DATA:${bytes.single}');
          case 'drain':
            await peer!.drainOutput();
            stdout.writeln('DRAINED');
          case 'pending':
            pendingRead = result(peer!.read(count: 1));
            stdout.writeln('PENDING');
          case 'pending-result':
            stdout.writeln('RESULT:${await pendingRead!}');
          case 'full':
            pendingWrite = result(peer!.write(Uint8List(8 * 1024 * 1024)));
            await Future<void>.delayed(const Duration(milliseconds: 100));
            pendingRead = result(peer.read(count: 1));
            pendingDrain = result(peer.drainOutput());
            await Future<void>.delayed(const Duration(milliseconds: 50));
            if (await result(worker.verifyTrustedPeer()) != 'RESOURCE_LIMIT')
              throw StateError('EXPECTED_FULL_PENDING_QUOTA');
            stdout.writeln('FULL_PENDING');
          case 'full-result':
            stdout.writeln(
              'RESULT:${await pendingWrite!},${await pendingRead!},${await pendingDrain!}',
            );
          case 'timeout':
            await peer!.read(
              count: 1,
              deadline: const Duration(milliseconds: 30),
            );
            throw StateError('EXPECTED_TIMEOUT');
          case 'disconnect':
            await worker.disconnect();
            stdout.writeln('DISCONNECTED');
          case 'disconnect-peer':
            await peer!.disconnect();
            stdout.writeln('DISCONNECTED');
          case 'close':
            await worker.close();
            stdout.writeln('CLOSED');
            await stdout.flush();
            return;
          default:
            throw StateError('INVALID_FIXTURE_COMMAND');
        }
      } on StateError catch (e) {
        stdout.writeln('ERR:${e.message}');
      }
      await stdout.flush();
    }
  } finally {
    if (lease != null) await lease.close();
    if (gate != null) await gate.close();
    await worker.close();
  }
}
