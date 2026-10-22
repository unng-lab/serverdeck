import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import '../../../serverdeck_windows/test/support/publication_mutex_fault.dart';
import 'operational_auth_actor.dart' as n;

const other = '92345678-1234-4234-8234-123456789abc';
Future<void> failed(Future<Object?> work, String code) async {
  try {
    await work;
  } on StateError catch (e) {
    n.check(e.message == code);
    return;
  }
  throw StateError('EXPECTED_GATE_FAILURE');
}

Future<void> settled(bool Function() check) async {
  final watch = Stopwatch()..start();
  while (!check()) {
    n.check(watch.elapsed < const Duration(seconds: 8));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<void> child(List<String> args) async {
  final root = args[2];
  n.ownRoot(root);
  final pipe = await PipeWorker.openOperationalClient(
    args[1],
    currentUserSid(),
    root,
  );
  final session = await OperationalBootstrapClient(
    pipe: pipe,
    generation: n.generation,
    token: n.token,
  ).authenticate();
  final gate = await session.peer.publicationGate(n.generation);
  OperationalPublicationLease? lease;
  final commands = StreamIterator(
    stdin.transform(utf8.decoder).transform(const LineSplitter()),
  );
  try {
    stdout.writeln('AUTH:${session.role.name}');
    while (await commands.moveNext()) {
      switch (commands.current) {
        case 'hold':
          stdout.writeln('WAIT');
          lease = await gate.acquire();
          stdout.writeln('HELD');
        case 'io':
          await session.peer.write([42]);
          stdout.writeln('IO');
        case 'release':
          final done = lease!.close();
          n.check(identical(done, lease.close()));
          await done;
          lease = null;
          stdout.writeln('RELEASED');
        case 'done':
          return;
        default:
          throw StateError('UNKNOWN_COMMAND');
      }
    }
  } finally {
    await lease?.close();
    try {
      await gate.close();
    } on StateError catch (e) {
      n.check(e.message == 'SERVICE_UNAVAILABLE');
    }
    await commands.cancel();
    await session.close();
    await pipe.close();
  }
}

Future<void> scenario(String root, String mode) async {
  n.ownRoot(root);
  final registry = OperationalSessions(generation: n.generation);
  final pair = await n.Pair.start(
    root,
    mode == 'owner' ? 'serverdeck.exe' : 'mcp.exe',
    registry,
  );
  OperationalPublicationGate? gate;
  try {
    await pair.exchange();
    n.check(await pair.next() == 'AUTH:${mode == 'owner' ? 'owner' : 'mcp'}');
    gate = await pair.peer!.publicationGate(n.generation);
    n.check(!operationalNativeObservationEnabled);
    await failed(
      Future.sync(() => gate!.observeNextAcquireDeliveryForTest()),
      'UNSUPPORTED',
    );
    await failed(pair.peer!.observeNextRevalidationForTest(), 'UNSUPPORTED');
    await failed(
      Future.sync(() => gate!.failNextLeaseReleaseForTest()),
      'UNSUPPORTED',
    );
    await failed(
      Future.sync(() => registry.failNextAuthorityLeaseReleaseForTest()),
      'UNSUPPORTED',
    );
    n.check(
      gate.localRole == BundlePeerRole.locald &&
          gate.generation == n.generation,
    );
    if (mode == 'startup-error') {
      final observer = await pair.peer!.publicationGate(n.generation);
      final fault = PublicationMutexFault(root, n.generation);
      try {
        fault.deny();
        await failed(gate.acquire(), 'SERVICE_UNAVAILABLE');
        fault.restore();
        await settled(() => gate!.activeAcquisitions == 0);
        n.check(gate.isClosed);
        await failed(gate.acquire(), 'SERVICE_UNAVAILABLE');
        await failed(observer.acquire(), 'SERVICE_UNAVAILABLE');
      } finally {
        fault.close();
        try {
          await observer.close();
        } on StateError catch (e) {
          n.check(e.message == 'SERVICE_UNAVAILABLE');
        }
      }
    } else if (mode == 'lease-quota') {
      final first = await gate.acquire();
      final pending = [for (var i = 0; i < 15; i++) gate.acquire()];
      for (final work in pending) {
        work.ignore();
      }
      n.check(gate.activeAcquisitions == 15 && gate.activeLeases == 1);
      await failed(gate.acquire(), 'RESOURCE_LIMIT');
      final closing = gate.close();
      for (final work in pending) {
        await failed(work, 'SERVICE_UNAVAILABLE');
      }
      await first.close();
      await closing;
    } else if (mode == 'late-close') {
      final pending = gate.acquire();
      pending.ignore();
      final closing = gate.close();
      await failed(pending, 'SERVICE_UNAVAILABLE');
      await closing;
      n.check(gate.activeAcquisitions == 0 && gate.activeLeases == 0);
      final observer = await pair.peer!.publicationGate(n.generation);
      try {
        final lease = await observer.acquire();
        await lease.close();
      } finally {
        await observer.close();
      }
    } else if (mode == 'close-held') {
      final lease = await gate.acquire();
      var closed = false;
      final closing = gate.close();
      closing.then<void>((_) {
        closed = true;
      }).ignore();
      n.check(identical(closing, gate.close()));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      n.check(!closed && gate.activeLeases == 1);
      await failed(gate.acquire(), 'SERVICE_UNAVAILABLE');
      await lease.close();
      await closing;
      n.check(closed && gate.activeLeases == 0);
    } else if (mode == 'contention') {
      final first = await gate.acquire();
      pair.child.stdin.writeln('hold');
      n.check(await pair.next() == 'WAIT');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      n.check(gate.activeLeases == 1);
      await first.close();
      n.check(await pair.next() == 'HELD');
      await failed(
        gate.acquire(deadline: const Duration(milliseconds: 200)),
        'TIMEOUT',
      );
      await settled(
        () => gate!.activeAcquisitions == 0 && gate.activeLeases == 0,
      );
      pair.child.stdin.writeln('release');
      n.check(await pair.next() == 'RELEASED');
      final next = await gate.acquire();
      await next.close();
    } else {
      pair.child.stdin.writeln('hold');
      n.check(await pair.next() == 'WAIT');
      n.check(await pair.next() == 'HELD');
      if (mode == 'timeout') {
        final watch = Stopwatch()..start();
        await failed(gate.acquire(), 'TIMEOUT');
        n.check(
          watch.elapsed >= const Duration(milliseconds: 4500) &&
              watch.elapsed < const Duration(seconds: 8),
        );
        await settled(() => gate!.activeAcquisitions == 0);
      } else if (mode == 'generation') {
        final different = await pair.peer!.publicationGate(other);
        try {
          final lease = await different.acquire();
          await lease.close();
        } finally {
          await different.close();
        }
        await failed(
          gate.acquire(deadline: const Duration(milliseconds: 100)),
          'TIMEOUT',
        );
        await settled(() => gate!.activeAcquisitions == 0);
      } else if (mode == 'quota') {
        final attempts = [for (var i = 0; i < 16; i++) gate.acquire()];
        for (final work in attempts) {
          work.ignore();
        }
        n.check(gate.activeAcquisitions == 16);
        await failed(gate.acquire(), 'RESOURCE_LIMIT');
        final closing = gate.close();
        n.check(identical(closing, gate.close()));
        for (final work in attempts) {
          await failed(work, 'SERVICE_UNAVAILABLE');
        }
        await closing;
        n.check(gate.activeAcquisitions == 0 && gate.activeLeases == 0);
      } else if (mode == 'abandon') {
        final observer = await pair.peer!.publicationGate(n.generation);
        pair.child.kill();
        await pair.child.exitCode;
        try {
          await failed(gate.acquire(), 'SERVICE_UNAVAILABLE');
          await settled(() => gate!.activeAcquisitions == 0);
          n.check(gate.isClosed && gate.activeLeases == 0);
          await failed(gate.acquire(), 'SERVICE_UNAVAILABLE');
          await failed(observer.acquire(), 'SERVICE_UNAVAILABLE');
          n.check(observer.isClosed);
        } finally {
          await failed(observer.close(), 'SERVICE_UNAVAILABLE');
        }
        return;
      } else if (mode == 'identity') {
        final manifest = File(p.join(root, 'foundation.manifest.json'));
        final original = manifest.readAsBytesSync();
        try {
          manifest.writeAsBytesSync([...original, 10]);
          await failed(gate.acquire(), 'UNAUTHORIZED');
        } finally {
          manifest.writeAsBytesSync(original);
        }
        n.check(gate.isClosed);
        await failed(gate.acquire(), 'SERVICE_UNAVAILABLE');
      } else if (mode == 'io' || mode == 'owner') {
        pair.child.stdin.writeln('io');
        n.check(
          (await pair.peer!.read(count: 1)).single == 42 &&
              await pair.next() == 'IO',
        );
      } else {
        throw StateError('UNKNOWN_MODE');
      }
      pair.child.stdin.writeln('release');
      n.check(await pair.next() == 'RELEASED');
    }
    pair.child.stdin.writeln('done');
    await n.finishClient(pair.child);
    n.check(await pair.child.exitCode == 0);
  } finally {
    try {
      await gate?.close();
    } on StateError catch (e) {
      n.check(e.message == 'SERVICE_UNAVAILABLE');
    }
    registry.stop();
    try {
      await pair.close();
    } catch (_) {
      stderr.write(await pair.errors);
      rethrow;
    }
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'client') {
      await child(args);
      return;
    }
    await scenario(args[0], args[1]);
    stdout.writeln('PASS:${args[1]}');
  } catch (error, stack) {
    stderr.writeln('PUBLICATION_GATE_FIXTURE_FAILED');
    if (error is StateError &&
        const {
          'UNAUTHORIZED',
          'SERVICE_UNAVAILABLE',
          'TIMEOUT',
          'RESOURCE_LIMIT',
          'PREREQUISITE_UNAVAILABLE',
        }.contains(error.message))
      stderr.writeln(error.message);
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
