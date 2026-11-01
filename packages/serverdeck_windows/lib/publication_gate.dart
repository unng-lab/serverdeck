import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart' as w;
import 'package:serverdeck_engine/platform/ports.dart';

import 'kernel_security.dart';
import 'mutex.dart';
import 'security.dart';
import 'publication_binding.dart';

final _publicationCreateMutex = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer Function(Pointer<w.SECURITY_ATTRIBUTES>, Int32, Pointer<Utf16>),
      Pointer Function(Pointer<w.SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)
    >('CreateMutexW');

final class _PublicationAttempt {
  final result = Completer<WindowsPublicationLease>();
  final settled = Completer<void>();
  bool retired = false;
  Timer? timer;
}

/// Logical acquisition and actual acquisition/late-release completion. Neither
/// future grants authority; an issued lease still belongs to its recipient.
final class WindowsPublicationAcquisition implements PublicationAcquisition {
  WindowsPublicationAcquisition._(this.result, this.settled) {
    result.ignore();
    settled.ignore();
  }
  final Future<WindowsPublicationLease> result;
  final Future<void> settled;
}

/// Synchronization only: identity comes from a verified native endpoint.
final class WindowsPublicationGate implements PublicationGate {
  WindowsPublicationGate._(
    this.generation,
    this._name,
    this._sid,
    this._identity,
    this._verifyCurrentProcess,
  );
  final String generation, _name, _sid;
  final RetainedProcessIdentity _identity;
  final void Function(RetainedProcessIdentity) _verifyCurrentProcess;
  w.HANDLE? _poison, _keeper;
  final _attempts = <_PublicationAttempt>{};
  final _leases = <WindowsPublicationLease>{};
  bool _closing = false, _failed = false;
  Future<void>? _closeFuture;
  bool _ready = false;
  int get activeAcquisitions => _attempts.length;
  int get activeLeases => _leases.length;
  bool get isClosed {
    if (!_ready || _closing || _failed) return true;
    if (_leases.any(
      (lease) => lease._closeFuture == null && !lease._native.isHeld,
    )) {
      _poisonGeneration();
      return true;
    }
    return false;
  }

  /// Internal native composition primitive, never a wire admission factory.
  /// Root policy checks the retained current process and any owned writer lease;
  /// the primitive itself enforces native owner/handle lifetime and ACL fencing.
  static Future<WindowsPublicationGate> open({
    required String ownerIdentity,
    required String appRoot,
    required String generation,
    required void Function(RetainedProcessIdentity) verifyCurrentProcess,
  }) async {
    if (currentUserSid() != ownerIdentity ||
        !p.isAbsolute(appRoot) ||
        p.normalize(appRoot) != appRoot)
      throw StateError('UNAUTHORIZED');
    final names = windowsPublicationIdentity(
      ownerIdentity: ownerIdentity,
      appRoot: appRoot,
      generation: generation,
    );
    final identity = RetainedProcessIdentity.open(pid);
    final gate = WindowsPublicationGate._(
      generation,
      names.mutexName,
      ownerIdentity,
      identity,
      verifyCurrentProcess,
    );
    try {
      gate._checkIdentity();
      final text = names.poisonName.toNativeUtf16();
      final mutexText = names.mutexName.toNativeUtf16();
      try {
        final security = SecurityAttributes(ownerOnlySddl(ownerIdentity));
        try {
          gate._poison = w.CreateEvent(
            security.pointer,
            true,
            false,
            w.PCWSTR(text),
          ).value;
          if (!gate._poison!.isValid) throw StateError('SERVICE_UNAVAILABLE');
          requireKernelOwnerAcl(gate._poison!, ownerIdentity, '0x1f0003');
          gate._keeper = w.HANDLE(
            _publicationCreateMutex(security.pointer, 0, mutexText),
          );
          if (!gate._keeper!.isValid) throw StateError('SERVICE_UNAVAILABLE');
          requireKernelOwnerAcl(gate._keeper!, ownerIdentity, '0x1f0001');
        } finally {
          security.close();
        }
      } finally {
        calloc.free(text);
        calloc.free(mutexText);
      }
      gate._ready = true;
      gate._check();
    } catch (_) {
      // Return the failed owned object so HostAuthority retains its cleanup.
      // Throwing away a partially-created native resource would lose that drain.
      gate._poisonGeneration();
    }
    return gate;
  }

  void _checkIdentity() {
    if (currentUserSid() != _sid || _identity.pid != pid) {
      throw StateError('UNAUTHORIZED');
    }
    _identity.revalidate();
    _verifyCurrentProcess(_identity);
    _identity.revalidate();
    if (currentUserSid() != _sid) throw StateError('UNAUTHORIZED');
  }

  void _check() {
    if (isClosed) throw StateError('SERVICE_UNAVAILABLE');
    try {
      _checkIdentity();
    } catch (_) {
      _poisonGeneration();
      throw StateError('UNAUTHORIZED');
    }
    if (w.WaitForSingleObject(_poison!, 0).value != 258) {
      _failed = true;
      throw StateError('SERVICE_UNAVAILABLE');
    }
  }

  void _poisonGeneration() {
    _failed = true;
    final poison = _poison;
    if (poison != null && poison.isValid) w.SetEvent(poison);
  }

  /// One absolute budget includes startup/contention; late work stays charged.
  Future<WindowsPublicationLease> acquire({
    Duration deadline = const Duration(seconds: 5),
  }) => beginAcquire(deadline: deadline).result;

  WindowsPublicationAcquisition beginAcquire({
    Duration deadline = const Duration(seconds: 5),
  }) {
    WindowsPublicationAcquisition refused(String code) =>
        WindowsPublicationAcquisition._(
          Future.error(StateError(code)),
          Future.value(),
        );
    if (isClosed) return refused('SERVICE_UNAVAILABLE');
    if (deadline <= Duration.zero) return refused('TIMEOUT');
    if (_attempts.length + _leases.length >= 16)
      return refused('RESOURCE_LIMIT');
    final budget = deadline < const Duration(seconds: 5)
        ? deadline
        : const Duration(seconds: 5);
    final attempt = _PublicationAttempt();
    attempt.result.future.ignore();
    attempt.settled.future.ignore();
    _attempts.add(attempt);
    attempt.timer = Timer(budget, () {
      attempt.retired = true;
      if (!attempt.result.isCompleted)
        attempt.result.completeError(StateError('TIMEOUT'));
    });
    final watch = Stopwatch()..start();
    _acquire(attempt, watch, budget)
        .then(
          (lease) async {
            if (attempt.retired || attempt.result.isCompleted) {
              await lease.close();
            } else {
              attempt.result.complete(lease);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!attempt.result.isCompleted) {
              final code =
                  error is StateError &&
                      const {
                        'TIMEOUT',
                        'UNAUTHORIZED',
                        'RESOURCE_LIMIT',
                        'SERVICE_UNAVAILABLE',
                      }.contains(error.message)
                  ? error.message
                  : 'SERVICE_UNAVAILABLE';
              attempt.result.completeError(StateError(code), stack);
            }
          },
        )
        .catchError((Object _) {
          _poisonGeneration();
        })
        .whenComplete(() {
          attempt.timer?.cancel();
          _attempts.remove(attempt);
          if (_failed) {
            attempt.settled.completeError(StateError('SERVICE_UNAVAILABLE'));
          } else {
            attempt.settled.complete();
          }
        })
        .ignore();
    return WindowsPublicationAcquisition._(
      attempt.result.future,
      attempt.settled.future,
    );
  }

  Future<WindowsPublicationLease> _acquire(
    _PublicationAttempt attempt,
    Stopwatch watch,
    Duration budget,
  ) async {
    while (true) {
      _check();
      if (attempt.retired || watch.elapsed >= budget)
        throw StateError('TIMEOUT');
      late final MutexLease native;
      try {
        native = await MutexLease.acquire(_name, _sid);
      } catch (_) {
        // Startup errors can include an uncertain native cleanup result. The
        // worker helper does not distinguish them, so retire conservatively.
        _poisonGeneration();
        throw StateError('SERVICE_UNAVAILABLE');
      }
      var transferred = false;
      try {
        if (native.abandoned) {
          _poisonGeneration();
          throw StateError('SERVICE_UNAVAILABLE');
        }
        _check();
        if (native.acquired && !native.isHeld) {
          _poisonGeneration();
          throw StateError('SERVICE_UNAVAILABLE');
        }
        if (attempt.retired || watch.elapsed >= budget)
          throw StateError('TIMEOUT');
        if (native.acquired) {
          final lease = WindowsPublicationLease._(this, native);
          _leases.add(lease);
          transferred = true;
          return lease;
        }
      } finally {
        if (!transferred) {
          try {
            await native.close();
          } catch (_) {
            _poisonGeneration();
            throw StateError('SERVICE_UNAVAILABLE');
          }
        }
      }
      final left = budget - watch.elapsed;
      if (left <= Duration.zero) throw StateError('TIMEOUT');
      await Future<void>.delayed(
        left < const Duration(milliseconds: 10)
            ? left
            : const Duration(milliseconds: 10),
      );
    }
  }

  /// Held publication ownership is released by its owner, never forced here.
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    final done = Completer<void>();
    _closeFuture = done.future;
    done.future.ignore();
    _closing = true;
    for (final attempt in _attempts) {
      attempt.retired = true;
      attempt.timer?.cancel();
      if (!attempt.result.isCompleted)
        attempt.result.completeError(StateError('SERVICE_UNAVAILABLE'));
    }
    Future<void>(() async {
      var failed = _failed;
      try {
        await Future.wait<void>([
          for (final attempt in _attempts.toList()) attempt.settled.future,
          for (final lease in _leases.toList()) lease.done,
        ]);
      } catch (_) {
        failed = true;
      }
      final poison = _poison, keeper = _keeper;
      if (poison != null &&
          poison.isValid &&
          w.WaitForSingleObject(poison, 0).value != 258)
        failed = true;
      try {
        if (!_identity.close()) failed = true;
      } catch (_) {
        failed = true;
      }
      if (keeper != null && keeper.isValid && !w.CloseHandle(keeper).value)
        failed = true;
      if (poison != null && poison.isValid && !w.CloseHandle(poison).value)
        failed = true;
      failed = failed || _failed;
      if (failed) throw StateError('SERVICE_UNAVAILABLE');
    }).then(done.complete, onError: done.completeError);
    return done.future;
  }
}

final class WindowsPublicationLease implements PublicationLease {
  WindowsPublicationLease._(this._gate, this._native) {
    _done.future.ignore();
  }
  final WindowsPublicationGate _gate;
  final MutexLease _native;
  final _done = Completer<void>();
  Future<void>? _closeFuture;
  Future<void> get done => _done.future;
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    _closeFuture = _done.future;
    Future<void>.sync(_native.close).then(
      (_) {
        _gate._leases.remove(this);
        _done.complete();
      },
      onError: (Object _) {
        _gate._poisonGeneration();
        _gate._leases.remove(this);
        _done.completeError(StateError('SERVICE_UNAVAILABLE'));
      },
    );
    return _done.future;
  }
}
