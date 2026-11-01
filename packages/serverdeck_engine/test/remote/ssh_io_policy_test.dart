import 'dart:async';
import 'dart:typed_data';

import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:test/test.dart';

import 'ssh_pool_lifecycle_test.dart' show settle, failure;

final pin = SshHostPin('ssh-ed25519', 'SHA256:${'A' * 43}');
final endpoint = SshEndpoint('unit.invalid', 22, 'unit');
final credential = SshCredential.password('unit-ephemeral-only');

// Provider events only. Actual pool, lease, read capture, quotas, timers and
// executor framing run unchanged. No sockets/SSH peer/isolate/files/processes.
final class Input implements StreamSink<Uint8List> {
  Input(this.inner, this.pause);
  final StreamSink<Uint8List> inner;
  final Future<void>? Function() pause;
  Future<void>? closing;
  @override
  void add(Uint8List value) => inner.add(value);
  @override
  void addError(Object error, [StackTrace? stack]) =>
      inner.addError(error, stack);
  @override
  Future<void> addStream(Stream<Uint8List> stream) async {
    await inner.addStream(stream);
  }

  @override
  Future<void> close() => closing ??= () async {
    await inner.close();
    await pause();
  }();
  @override
  Future<void> get done => closing ?? inner.done.then<void>((_) {});
}

final class Session implements SshIoSession {
  final output = StreamController<Uint8List>(),
      errors = StreamController<Uint8List>();
  final input = StreamController<Uint8List>();
  final completed = Completer<void>();
  final received = <Uint8List>[];
  void Function(Uint8List)? onInput;
  Completer<void>? stdinPause;
  late final inputSink = Input(input.sink, () => stdinPause?.future);
  bool autoClose = true, finishing = false;
  int closes = 0;
  bool throwClose = false;
  Session() {
    input.stream.listen((chunk) {
      received.add(Uint8List.fromList(chunk));
      onInput?.call(Uint8List.fromList(chunk));
    });
  }
  @override
  Stream<Uint8List> get stdout => output.stream;
  @override
  Stream<Uint8List> get stderr => errors.stream;
  @override
  StreamSink<Uint8List> get stdin => inputSink;
  @override
  Future<void> get done => completed.future;
  @override
  int? exitCode = 0;
  @override
  void close() {
    if (throwClose) throw StateError('PRIVATE_SESSION_CLOSE');
    closes++;
    if (autoClose) finish().ignore();
  }

  Future<void> finish() async {
    if (finishing) return done;
    finishing = true;
    await input.close();
    await Future.wait([output.close(), errors.close()]);
    if (!completed.isCompleted) completed.complete();
  }
}

final class Client implements SshIoClient {
  final sessions = <Session>[], commands = <SshIoCommand>[];
  final completed = Completer<void>();
  Future<void>? closing;
  bool autoClose = true;
  bool throwClose = false;
  void Function(Session, SshIoCommand)? onExecute;
  @override
  Future<void> get done => completed.future;
  @override
  Future<SshIoSession> execute(SshIoCommand command) async {
    commands.add(command);
    final session = Session();
    sessions.add(session);
    onExecute?.call(session, command);
    return session;
  }

  @override
  Future<void> close() {
    if (throwClose) throw StateError('PRIVATE_CLIENT_CLOSE');
    return closing ??= () async {
      for (final session in sessions) session.close();
      await Future.wait([for (final session in sessions) session.done]);
      if (autoClose && !completed.isCompleted) completed.complete();
      await done;
    }();
  }

  Future<void> finish() async {
    await Future.wait([for (final session in sessions) session.finish()]);
    if (!completed.isCompleted) completed.complete();
  }
}

final class Attempt implements SshIoAttempt {
  final client = Client();
  final ready = Completer<SshIoClient>(), drained = Completer<void>();
  int cancels = 0;
  bool late = false, holdDrain = false;
  bool throwCancel = false;
  Attempt() {
    ready.future.ignore();
  }
  @override
  Future<SshIoClient> get result => ready.future;
  @override
  Future<void> get settled => drained.future;
  @override
  void cancel() {
    cancels++;
    if (throwCancel) throw StateError('PRIVATE_CANCEL');
    if (cancels > 1 || late) return;
    if (!ready.isCompleted)
      ready.completeError(
        const SshTransportFailure(SshTransportCode.CANCELLED),
      );
    client
        .close()
        .then<void>(
          (_) {
            if (!holdDrain && !drained.isCompleted) drained.complete();
          },
          onError: (Object error, StackTrace stack) {
            if (!drained.isCompleted) drained.completeError(error, stack);
          },
        )
        .ignore();
  }

  void drain() {
    if (!drained.isCompleted) drained.complete();
  }
}

final class Io implements SshIoFactory {
  final attempts = <Attempt>[];
  SshHostPin? observed;
  bool verify = true, complete = true, late = false, holdDrain = false;
  void Function()? onStart;
  @override
  SshIoAttempt start(
    SshEndpoint endpoint,
    SshCredential? credential, {
    required Duration deadline,
    required bool Function(SshHostPin) verifyHostPin,
  }) {
    expect(deadline, greaterThan(Duration.zero));
    expect(deadline, lessThanOrEqualTo(const Duration(seconds: 15)));
    final attempt = Attempt()
      ..late = late
      ..holdDrain = holdDrain;
    attempts.add(attempt);
    final accepted = verify && verifyHostPin(observed ?? pin);
    onStart?.call();
    if (complete) {
      if (credential == null && !accepted)
        attempt.ready.completeError(
          const SshTransportFailure(SshTransportCode.CONNECTION_FAILED),
        );
      else
        attempt.ready.complete(attempt.client);
    }
    return attempt;
  }
}

Future<SshLease> connect(SshTransportPool pool) =>
    pool.connect(endpoint, pin, credential).result;

void main() {
  test('session done error is observed before pending stdin close', () async {
    final io = Io(), pool = SshTransportPool(io: io);
    final lease = await connect(pool);
    io.attempts.single.client.onExecute = (session, _) {
      session.stdinPause = Completer<void>();
    };
    final read = lease.read(const SshReadRequest.system());
    final result = expectLater(read.result, failure()),
        done = expectLater(read.settled, failure());
    await settle();
    final actual = io.attempts.single, session = actual.client.sessions.single;
    session.completed.completeError(StateError('PRIVATE_EARLY_SESSION_DONE'));
    await Future.wait([result, done]);
    expect(() => pool.reserve(), failure());
    await expectLater(pool.close(), failure());
    expect(pool.activeTransports, 1);
    session.stdinPause!.complete();
    await session.finish().then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    if (!actual.client.completed.isCompleted)
      actual.client.completed.complete();
    actual.drain();
    await settle();
  });
  for (final executor in [false, true]) {
    test(
      'throwing session close reports own failure before pending physical done: executor=$executor',
      () async {
        final io = Io(), pool = SshTransportPool(io: io);
        final lease = await connect(pool);
        SshAttempt<SshReadOutput>? read;
        SshExecutorChannel? channel;
        Future<void> own;
        if (executor) {
          final opening = lease.openExecutor();
          channel = await opening.result;
          own = channel.done;
        } else {
          read = lease.read(const SshReadRequest.system());
          read.result.ignore();
          own = read.settled;
          await settle();
        }
        final actual = io.attempts.single,
            session = actual.client.sessions.single;
        session.autoClose = false;
        session.throwClose = true;
        final failed = expectLater(own, failure());
        final pause = pool.suspend();
        await failed;
        await expectLater(pause.settled, failure());
        expect(session.completed.isCompleted, isFalse);
        expect(() => pool.resume(pause), failure());
        expect(pool.activeTransports, 1);
        session.throwClose = false;
        await session.finish();
        if (!actual.client.completed.isCompleted)
          actual.client.completed.complete();
        actual.drain();
        await settle();
        await expectLater(pool.close(), failure());
      },
    );
  }
  test(
    'probe cannot publish observed pin after a failed physical drain',
    () async {
      final io = Io()..holdDrain = true;
      final pool = SshTransportPool(io: io);
      final probe = pool.probe(endpoint);
      final result = expectLater(probe.result, failure());
      final done = expectLater(probe.settled, failure());
      await settle();
      io.attempts.single.drained.completeError(
        StateError('PRIVATE_PROBE_DRAIN'),
      );
      await Future.wait([result, done]);
      expect(pool.activeTransports, 1);
      expect(() => pool.reserve(), failure());
      await expectLater(pool.close(), failure());
    },
  );
  test('byte session cleanup failure stays charged and reports failure, not closure', () async {
    final io = Io(), pool = SshTransportPool(io: io);
    final lease = await connect(pool);
    final read = lease.read(const SshReadRequest.system());
    final failed = expectLater(read.settled, failure());
    await settle();
    final actual = io.attempts.single, session = actual.client.sessions.single;
    session.throwClose = true;
    session.output.add(Uint8List.fromList([65]));
    await session.finish();
    await read.result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    await failed;
    await expectLater(lease.done, failure());
    await expectLater(pool.close(), failure());
    expect(pool.activeTransports, 1);
    await actual.client.finish();
    actual.drain();
    await settle();
  });
  test('provider drain error reports safe failed closure and stops other owned clients', () async {
    final io = Io(), pool = SshTransportPool(io: io);
    final first = await connect(pool), second = await connect(pool);
    final failed = expectLater(
      first.done,
      failure(SshTransportCode.SERVICE_UNAVAILABLE),
    );
    io.attempts.first.drained.completeError(StateError('PRIVATE_DRAIN_ERROR'));
    await failed;
    expect(() => pool.reserve(), failure());
    expect(() => second.read(const SshReadRequest.system()), failure());
    expect(() => second.openExecutor(), failure());
    await expectLater(pool.close(), failure());
    await second.done;
    expect(io.attempts.last.cancels, greaterThan(0));
    expect(pool.activeTransports, 1);
    await expectLater(first.close(), failure());
    expect(io.attempts.length, 2);
  });
  for (final cancel in [true, false]) {
    test(
      'synchronous cleanup failure is observable and cannot authorize resume: cancel=$cancel',
      () async {
        final io = Io(), pool = SshTransportPool(io: io);
        final first = await connect(pool), second = await connect(pool);
        final actual = io.attempts.first;
        actual.holdDrain = true;
        if (cancel)
          actual.throwCancel = true;
        else
          actual.client.throwClose = true;
        final failed = expectLater(first.done, failure());
        final pause = pool.suspend();
        await failed;
        await expectLater(pause.settled, failure());
        await second.done;
        expect(io.attempts.last.cancels, greaterThan(0));
        expect(() => pool.resume(pause), failure());
        expect(() => pool.reserve(), failure());
        expect(pool.activeTransports, 1);
        await actual.client.finish();
        actual.drain();
        await settle();
        expect(pool.activeTransports, 1);
        await expectLater(pool.close(), failure());
      },
    );
  }
  test('fixed executor shares actual four-channel read budget', () async {
    final io = Io(), pool = SshTransportPool(io: io);
    final lease = await connect(pool);
    final executor = lease.openExecutor();
    final channel = await executor.result;
    expect(io.attempts.single.client.commands.single.isExecutor, isTrue);
    final reads = [
      for (var i = 0; i < 3; i++) lease.read(const SshReadRequest.units()),
    ];
    expect(
      () => lease.openExecutor(),
      failure(SshTransportCode.RESOURCE_LIMIT),
    );
    expect(
      () => lease.read(const SshReadRequest.system()),
      failure(SshTransportCode.RESOURCE_LIMIT),
    );
    await settle();
    final sessions = io.attempts.single.client.sessions;
    for (var i = 0; i < reads.length; i++) {
      await sessions[i + 1].finish();
      await reads[i].result;
      await reads[i].settled;
    }
    await channel.close();
    await executor.settled;
    await lease.close();
    await pool.close();
  });
  test(
    'shorter original connect deadline cannot release late provider slot',
    () async {
      final io = Io()
        ..complete = false
        ..late = true;
      final pool = SshTransportPool(io: io);
      final opening = pool.connect(
        endpoint,
        pin,
        credential,
        deadline: const Duration(milliseconds: 20),
      );
      await expectLater(opening.result, failure(SshTransportCode.TIMEOUT));
      expect(pool.activeTransports, 1);
      final actual = io.attempts.single;
      actual.ready.complete(actual.client);
      await settle();
      expect(actual.client.closing, isNotNull);
      expect(pool.activeTransports, 1);
      actual.drain();
      await opening.settled;
      expect(pool.activeTransports, 0);
      await pool.close();
    },
  );
  test('actual pool shares reservation/connection two-slot budget and fixed read capture', () async {
    final io = Io();
    final shared = SshTransportPool(io: io);
    final reservation = shared.reserve();
    final first = await reservation
        .connect(
          endpoint,
          pin,
          credential,
          deadline: const Duration(seconds: 15),
        )
        .result;
    final second = await connect(shared);
    expect(shared.activeTransports, 2);
    expect(() => shared.reserve(), failure(SshTransportCode.RESOURCE_LIMIT));
    expect(io.attempts.length, 2);
    final reading = first.read(const SshReadRequest.system());
    await settle();
    final session = io.attempts.first.client.sessions.single;
    session.output.add(Uint8List.fromList([65, 66, 67]));
    await session.finish();
    final result = await reading.result;
    expect(result.bytes, [65, 66, 67]);
    expect(result.exitCode, 0);
    expect(
      io.attempts.first.client.commands.single.read!.source,
      SshReadSource.system,
    );
    await reading.settled;
    await first.close();
    await second.close();
    await shared.close();
    expect(shared.activeTransports, 0);
  });
  for (final mismatch in [false, true]) {
    test(
      'unverified or mismatched provider never publishes lease: mismatch=$mismatch',
      () async {
        final io = Io()..verify = mismatch;
        if (mismatch)
          io.observed = SshHostPin('ssh-ed25519', 'SHA256:${'B' * 42}A');
        final pool = SshTransportPool(io: io);
        await expectLater(
          connect(pool),
          failure(SshTransportCode.TRUST_CHANGED),
        );
        await pool.close();
        expect(pool.activeTransports, 0);
        expect(io.attempts.single.client.commands, isEmpty);
      },
    );
  }
  test(
    'probe observed pin waits actual provider drain, never exposes client',
    () async {
      final io = Io()..holdDrain = true;
      final pool = SshTransportPool(io: io);
      final probe = pool.probe(endpoint);
      var replied = false;
      probe.result.then<void>((_) {
        replied = true;
      }).ignore();
      await settle();
      expect(replied, isFalse);
      expect(pool.activeTransports, 1);
      io.attempts.single.drain();
      expect(await probe.result, pin);
      await probe.settled;
      expect(io.attempts.single.client.commands, isEmpty);
      await pool.close();
    },
  );
  test(
    'cancelled late client and original provider drain retain real slots',
    () async {
      final io = Io()
        ..complete = false
        ..late = true;
      final pool = SshTransportPool(io: io);
      final opening = pool.connect(endpoint, pin, credential);
      final rejected = expectLater(
        opening.result,
        failure(SshTransportCode.CANCELLED),
      );
      opening.cancel();
      await rejected;
      final other = pool.reserve();
      expect(() => pool.reserve(), failure(SshTransportCode.RESOURCE_LIMIT));
      final actual = io.attempts.single;
      actual.ready.complete(actual.client);
      await settle();
      expect(actual.client.closing, isNotNull);
      expect(pool.activeTransports, 2);
      actual.drain();
      await opening.settled;
      expect(pool.activeTransports, 1);
      other.close();
      await pool.close();
    },
  );
  test(
    'factory synchronous stop still cancels and owns returned attempt',
    () async {
      final io = Io()..complete = false;
      final pool = SshTransportPool(io: io);
      Future<void>? closing;
      io.onStart = () => closing = pool.close();
      final opening = pool.connect(endpoint, pin, credential);
      await expectLater(
        opening.result,
        failure(SshTransportCode.SERVICE_UNAVAILABLE),
      );
      await closing;
      expect(io.attempts.single.cancels, greaterThan(0));
      expect(pool.activeTransports, 0);
    },
  );
  test(
    'four-channel limit and output truncation are actual lease policy',
    () async {
      final io = Io();
      final shared = SshTransportPool(io: io);
      final connection = await connect(shared);
      final reads = [
        for (var i = 0; i < 4; i++)
          connection.read(const SshReadRequest.system()),
      ];
      expect(
        () => connection.read(const SshReadRequest.metrics()),
        failure(SshTransportCode.RESOURCE_LIMIT),
      );
      await settle();
      final sessions = io.attempts.single.client.sessions;
      sessions.first.output.add(Uint8List(256 * 1024 + 1));
      final value = await reads.first.result;
      expect(value.bytes.length, 256 * 1024);
      expect(value.truncated, isTrue);
      await reads.first.settled;
      for (var i = 1; i < reads.length; i++) {
        await sessions[i].finish();
        await reads[i].result;
        await reads[i].settled;
      }
      await connection.close();
      await shared.close();
    },
  );
  test('pause waits provider and channel physical completion after logical cancellation', () async {
    final io = Io(), pool = SshTransportPool(io: io);
    final lease = await connect(pool);
    final reading = lease.read(SshReadRequest.journal());
    await settle();
    final actual = io.attempts.single, session = actual.client.sessions.single;
    actual.holdDrain = true;
    session.autoClose = false;
    final pause = pool.suspend();
    await expectLater(
      reading.result,
      failure(SshTransportCode.SERVICE_UNAVAILABLE),
    );
    var drained = false;
    pause.settled.then<void>((_) {
      drained = true;
    }).ignore();
    await settle();
    expect(drained, isFalse);
    expect(pool.activeTransports, 1);
    await session.finish();
    await settle();
    expect(drained, isFalse);
    actual.drain();
    await pause.settled;
    pool.resume(pause);
    await pool.close();
  });
}
