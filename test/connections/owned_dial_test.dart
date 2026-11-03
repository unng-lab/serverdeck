import 'dart:async';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/owned_dial.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/runtime/owned_work.dart';

Future<void> turn() => Future<void>.delayed(Duration.zero);
Matcher failure(FailureCode code) =>
    isA<OperationFailure>().having((e) => e.code, 'code', code);

final class Task implements SshDialTask {
  Task() {
    value.future.ignore();
  }
  final value = Completer<SSHSocket>();
  int cancels = 0;
  bool failCancel = false, failGetter = false;
  @override
  Future<SSHSocket> get socket {
    if (failGetter) throw StateError('SYNTHETIC_GETTER_SECRET');
    return value.future;
  }

  @override
  void cancel() {
    cancels++;
    if (failCancel) throw StateError('SYNTHETIC_CANCEL_SECRET');
  }
}

final class MemorySocket extends Fake implements SSHSocket {
  final confirmed = Completer<void>();
  int closes = 0, destroys = 0, failedCloses = 0;
  bool failDestroy = false, failDone = false;
  @override
  Future<void> get done {
    if (failDone) throw StateError('SYNTHETIC_DONE_GETTER');
    return confirmed.future;
  }

  @override
  Future<void> close() {
    closes++;
    if (closes <= failedCloses)
      return Future.error(StateError('SYNTHETIC_CLOSE_SECRET'));
    return Future<void>.value();
  }

  @override
  void destroy() {
    destroys++;
    if (failDestroy) throw StateError('SYNTHETIC_DESTROY_SECRET');
  }
}

final class SyntheticNativeSocket extends Fake implements Socket {
  final confirmed = Completer<void>();
  int closes = 0, destroys = 0, flushes = 0;
  List<int>? sent;
  bool failDone = false;
  @override
  Future<void> get done {
    if (failDone) throw StateError('SYNTHETIC_DONE_GETTER');
    return confirmed.future;
  }

  @override
  Future<Socket> close() {
    closes++;
    return confirmed.future.then((_) => this);
  }

  @override
  void destroy() => destroys++;
  @override
  Future<void> flush() async {
    flushes++;
  }

  @override
  void add(List<int> bytes) => sent = bytes;
}

void main() {
  test(
    'done getter failure retains unconfirmed dial socket for cleanup retry',
    () async {
      final task = Task(), socket = MemorySocket()..failDone = true;
      final dial = OwnedSshDial(
        'synthetic.invalid',
        22,
        begin: (_, _) async => task,
      );
      task.value.complete(socket);
      await dial.socket;
      await expectLater(
        dial.close(),
        throwsA(failure(FailureCode.cleanupRequired)),
      );
      expect(socket.closes, 1);
      expect(socket.confirmed.isCompleted, isFalse);
      socket.failDone = false;
      socket.confirmed.complete();
      await dial.close();
      expect(socket.closes, 2);
    },
  );
  test('native errored close plus throwing done getter is uncertain until retry obtains confirmation', () async {
    final socket = SyntheticNativeSocket()..failDone = true;
    final native = NativeSshSocket(socket);
    final failed = expectLater(
      native.close(),
      throwsA(failure(FailureCode.cleanupRequired)),
    );
    socket.confirmed.completeError(StateError('SYNTHETIC_RESET'));
    await failed;
    expect(socket.closes, 1);
    socket.failDone = false;
    await native.close();
    expect(socket.closes, 2);
  });
  test(
    'factory begins synchronously and resource is transferred exactly once',
    () async {
      final task = Task(), socket = MemorySocket();
      var started = false;
      final dial = OwnedSshDial(
        'synthetic.invalid',
        22,
        begin: (host, port) {
          started = true;
          expect(host, 'synthetic.invalid');
          expect(port, 22);
          return Future.value(task);
        },
      );
      expect(started, isTrue);
      expect(() => dial.takeSocket(), throwsA(isA<WorkCancelled>()));
      task.value.complete(socket);
      expect(await dial.socket, same(socket));
      expect(dial.takeSocket(), same(socket));
      expect(dial.transferred, isTrue);
      expect(() => dial.takeSocket(), throwsA(isA<WorkCancelled>()));
      await dial.close();
      expect(task.cancels, 0);
      expect(socket.closes, 0);
      expect(socket.destroys, 0);
      // New owner, rather than the dial, confirms this transferred handle.
      socket.confirmed.complete();
    },
  );
  test('cancel before factory exists returns promptly but cleanup waits for exact late handle', () async {
    final factory = Completer<SshDialTask>(),
        task = Task(),
        socket = MemorySocket();
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) => factory.future,
    );
    final rejected = expectLater(dial.socket, throwsA(isA<WorkCancelled>()));
    var closed = false;
    final closing = dial.close().then((_) {
      closed = true;
    });
    await rejected;
    await turn();
    expect(closed, isFalse);
    factory.complete(task);
    await turn();
    expect(task.cancels, 1);
    expect(closed, isFalse);
    task.value.complete(socket);
    await turn();
    expect(socket.destroys, 1);
    expect(socket.closes, 1);
    expect(closed, isFalse);
    socket.confirmed.complete();
    await closing;
    expect(closed, isTrue);
    expect(() => dial.takeSocket(), throwsA(isA<WorkCancelled>()));
    await dial.close();
    expect(socket.closes, 1);
  });
  test(
    'known task cancellation does not confirm closure before its outcome',
    () async {
      final task = Task();
      final dial = OwnedSshDial(
        'synthetic.invalid',
        22,
        begin: (_, _) async => task,
      );
      final rejected = expectLater(dial.socket, throwsA(isA<WorkCancelled>()));
      await turn();
      var closed = false;
      final closing = dial.close().then((_) {
        closed = true;
      });
      await rejected;
      await turn();
      expect(task.cancels, 1);
      expect(closed, isFalse);
      task.value.completeError(StateError('SYNTHETIC_CANCEL_ACK'));
      await closing;
      expect(closed, isTrue);
    },
  );
  test('connected but not transferred socket remains owned and awaits physical done', () async {
    final task = Task(), socket = MemorySocket();
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) async => task,
    );
    task.value.complete(socket);
    await dial.socket;
    var closed = false;
    final closing = dial.close().then((_) {
      closed = true;
    });
    await turn();
    expect(task.cancels, 0);
    expect(socket.closes, 1);
    expect(closed, isFalse);
    socket.confirmed.complete();
    await closing;
    expect(closed, isTrue);
  });
  for (final synchronous in [false, true]) {
    test(
      'factory error is fixed and has no remaining handle synchronous=$synchronous',
      () async {
        final dial = OwnedSshDial(
          'synthetic.invalid',
          22,
          begin: (_, _) {
            if (synchronous) throw StateError('SYNTHETIC_FACTORY_SECRET');
            return Future.error(StateError('SYNTHETIC_FACTORY_SECRET'));
          },
        );
        await expectLater(
          dial.socket,
          throwsA(failure(FailureCode.networkError)),
        );
        await dial.close();
        expect(() => dial.takeSocket(), throwsA(isA<WorkCancelled>()));
      },
    );
  }
  test('late factory failure completes retained cleanup without reviving cancelled result', () async {
    final factory = Completer<SshDialTask>();
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) => factory.future,
    );
    final rejected = expectLater(dial.socket, throwsA(isA<WorkCancelled>()));
    final closing = dial.close();
    await rejected;
    factory.completeError(StateError('SYNTHETIC_FACTORY_SECRET'));
    await closing;
    await expectLater(dial.socket, throwsA(isA<WorkCancelled>()));
  });
  test('task connection error is fixed and cleanup needs no socket', () async {
    final task = Task();
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) async => task,
    );
    task.value.completeError(StateError('SYNTHETIC_ENDPOINT_SECRET'));
    await expectLater(dial.socket, throwsA(failure(FailureCode.networkError)));
    await dial.close();
    expect(task.cancels, 0);
  });
  test('failed cancellation retains task and retry closes a later connected socket', () async {
    final task = Task()..failCancel = true;
    final socket = MemorySocket();
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) async => task,
    );
    final rejected = expectLater(dial.socket, throwsA(isA<WorkCancelled>()));
    await turn();
    await expectLater(
      dial.close(),
      throwsA(failure(FailureCode.cleanupRequired)),
    );
    await rejected;
    task.value.complete(socket);
    await turn();
    socket.confirmed.complete();
    await dial.close();
    expect(task.cancels, 1);
    expect(socket.closes, 1);
  });
  test('failed close remains retryable on the same exact socket', () async {
    final task = Task(), socket = MemorySocket()..failedCloses = 1;
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) async => task,
    );
    task.value.complete(socket);
    await dial.socket;
    await expectLater(
      dial.close(),
      throwsA(failure(FailureCode.cleanupRequired)),
    );
    socket.confirmed.complete();
    await dial.close();
    expect(socket.closes, 2);
    expect(socket.destroys, 2);
  });
  test(
    'failed destroy does not prevent a close which confirms the exact resource',
    () async {
      final task = Task(), socket = MemorySocket()..failDestroy = true;
      final dial = OwnedSshDial(
        'synthetic.invalid',
        22,
        begin: (_, _) async => task,
      );
      task.value.complete(socket);
      await dial.socket;
      socket.confirmed.complete();
      await dial.close();
      expect(socket.destroys, 1);
      expect(socket.closes, 1);
    },
  );
  test('throwing task getter retains uncertain task and retry can attach its actual outcome', () async {
    final task = Task()..failGetter = true;
    final dial = OwnedSshDial(
      'synthetic.invalid',
      22,
      begin: (_, _) async => task,
    );
    await expectLater(dial.socket, throwsA(failure(FailureCode.networkError)));
    await expectLater(
      dial.close(),
      throwsA(failure(FailureCode.cleanupRequired)),
    );
    expect(task.cancels, 1);
    task.failGetter = false;
    task.value.completeError(StateError('SYNTHETIC_CANCEL_ACK'));
    await dial.close();
    expect(task.cancels, 2);
  });
  test(
    'concurrent close callers share retained closure and cancel only once',
    () async {
      final task = Task();
      final dial = OwnedSshDial(
        'synthetic.invalid',
        22,
        begin: (_, _) async => task,
      );
      final rejected = expectLater(dial.socket, throwsA(isA<WorkCancelled>()));
      await turn();
      final first = dial.close(), second = dial.close();
      expect(first, same(second));
      await rejected;
      await turn();
      expect(task.cancels, 1);
      task.value.completeError(StateError('SYNTHETIC_CANCEL_ACK'));
      await Future.wait([first, second]);
    },
  );
  test('native socket component forwards only to synthetic Socket and confirms errored done as closed', () async {
    final socket = SyntheticNativeSocket(),
        adapter = NativeSshSocket(SyntheticNativeSocket());
    expect(adapter.stream, same(adapter.socket));
    expect(adapter.sink, same(adapter.socket));
    final native = NativeSshSocket(socket);
    native.sink.add([1, 2, 3]);
    await native.flush();
    expect(socket.sent, [1, 2, 3]);
    expect(socket.flushes, 1);
    final closing = native.close();
    socket.confirmed.completeError(StateError('SYNTHETIC_RESET'));
    await closing;
    expect(socket.closes, 1);
    native.destroy();
    expect(socket.destroys, 1);
  });
}
