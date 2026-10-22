part of 'pipe_worker.dart';

final _publicationCreateMutex = DynamicLibrary.open('kernel32.dll')
    .lookupFunction<
      Pointer Function(Pointer<w.SECURITY_ATTRIBUTES>, Int32, Pointer<Utf16>),
      Pointer Function(Pointer<w.SECURITY_ATTRIBUTES>, int, Pointer<Utf16>)
    >('CreateMutexW');

final class _PublicationAttempt {
  final result = Completer<OperationalPublicationLease>();
  final settled = Completer<void>();
  bool retired = false;
  Timer? timer;
}

/// Logical acquisition and actual acquisition/late-release completion. Neither
/// future grants authority; an issued lease still belongs to its recipient.
final class OperationalPublicationAcquisition {
  OperationalPublicationAcquisition._(this.result, this.settled) {
    result.ignore();
    settled.ignore();
  }
  final Future<OperationalPublicationLease> result;
  final Future<void> settled;
}

/// Synchronization only: identity comes from a verified native endpoint.
final class OperationalPublicationGate {
  OperationalPublicationGate._(
    this.generation,
    this.localRole,
    this._name,
    this._sid,
    this._identity,
    this._proof,
    this._poison,
    this._keeper,
  );
  final String generation, _name, _sid;
  final BundlePeerRole localRole;
  final RetainedProcessIdentity _identity;
  final VerifiedBundlePeer _proof;
  final w.HANDLE _poison, _keeper;
  final _attempts = <_PublicationAttempt>{};
  final _leases = <OperationalPublicationLease>{};
  bool _closing = false, _failed = false;
  Future<void>? _closeFuture;
  _NativeObservationPause? _testAcquirePause;
  bool _testReleaseFailure = false;
  int get activeAcquisitions => _attempts.length;
  int get activeLeases => _leases.length;
  bool get isClosed => _closing || _failed;

  void failNextLeaseReleaseForTest() {
    if (!operationalNativeObservationEnabled) throw StateError('UNSUPPORTED');
    _check();
    if (_testReleaseFailure || _attempts.isNotEmpty || _leases.isNotEmpty)
      throw StateError('RESOURCE_LIMIT');
    _testReleaseFailure = true;
  }

  OperationalNativeObservation observeNextAcquireDeliveryForTest() {
    if (!operationalNativeObservationEnabled) throw StateError('UNSUPPORTED');
    _check();
    if (_testAcquirePause != null) throw StateError('RESOURCE_LIMIT');
    final pause = _testAcquirePause = _NativeObservationPause();
    return OperationalNativeObservation._(pause.reached.future, () async {
      pause.retire();
    });
  }

  static Future<OperationalPublicationGate> _open(
    List metadata,
    String generation,
    BundlePeerRole expected,
  ) async {
    if (metadata.length != 3 || metadata.any((v) => v is! String))
      throw StateError('UNAUTHORIZED');
    final sid = metadata[0] as String, root = metadata[1] as String;
    if (metadata[2] != expected.name || sid != currentUserSid())
      throw StateError('UNAUTHORIZED');
    final bundle = await verifyMcpBuildBundle(root);
    final identity = RetainedProcessIdentity.open(pid);
    w.HANDLE? poison, keeper;
    try {
      final proof = bundle.verifyPeer(identity, sid);
      if (proof.role != expected) throw StateError('UNAUTHORIZED');
      final digest = const DartSha256()
          .hashSync(
            utf8.encode(
              'serverdeck-next-publication-v1\n$sid\n$root\n$generation',
            ),
          )
          .bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final name = 'Global\\ServerDeckNext.v1.$digest';
      final text = '$name.poison'.toNativeUtf16();
      final mutexText = name.toNativeUtf16();
      final security = SecurityAttributes(ownerOnlySddl(sid));
      try {
        poison = w.CreateEvent(
          security.pointer,
          true,
          false,
          w.PCWSTR(text),
        ).value;
        if (!poison.isValid) throw StateError('SERVICE_UNAVAILABLE');
        requireKernelOwnerAcl(poison, sid, '0x1f0003');
        // Keep the kernel object alive across holder crash so abandonment
        // cannot disappear when its owning process closes the last handle.
        keeper = w.HANDLE(
          _publicationCreateMutex(security.pointer, 0, mutexText),
        );
        if (!keeper.isValid) throw StateError('SERVICE_UNAVAILABLE');
        requireKernelOwnerAcl(keeper, sid, '0x1f0001');
      } finally {
        security.close();
        calloc.free(text);
        calloc.free(mutexText);
      }
      final gate = OperationalPublicationGate._(
        generation,
        expected,
        name,
        sid,
        identity,
        proof,
        poison,
        keeper,
      );
      gate._check();
      return gate;
    } catch (_) {
      if (poison != null && poison.isValid) w.CloseHandle(poison);
      if (keeper != null && keeper.isValid) w.CloseHandle(keeper);
      identity.close();
      throw StateError('SERVICE_UNAVAILABLE');
    }
  }

  void _check() {
    if (_closing || _failed) throw StateError('SERVICE_UNAVAILABLE');
    try {
      _proof.revalidate();
    } catch (_) {
      _poisonGeneration();
      throw StateError('UNAUTHORIZED');
    }
    if (w.WaitForSingleObject(_poison, 0).value != 258) {
      _failed = true;
      throw StateError('SERVICE_UNAVAILABLE');
    }
  }

  void _poisonGeneration() {
    _failed = true;
    w.SetEvent(_poison);
  }

  /// One absolute budget includes startup/contention; late work stays charged.
  Future<OperationalPublicationLease> acquire({
    Duration deadline = const Duration(seconds: 5),
  }) => beginAcquire(deadline: deadline).result;

  OperationalPublicationAcquisition beginAcquire({
    Duration deadline = const Duration(seconds: 5),
  }) {
    OperationalPublicationAcquisition refused(String code) =>
        OperationalPublicationAcquisition._(
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
    return OperationalPublicationAcquisition._(
      attempt.result.future,
      attempt.settled.future,
    );
  }

  Future<OperationalPublicationLease> _acquire(
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
        native = await MutexLease.acquire(
          _name,
          _sid,
          testWrongThreadRelease:
              operationalNativeObservationEnabled && _testReleaseFailure,
        );
        if (native.acquired) _testReleaseFailure = false;
      } catch (_) {
        // Startup errors can include an uncertain native cleanup result. The
        // legacy helper does not distinguish them, so retire conservatively.
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
        if (attempt.retired || watch.elapsed >= budget)
          throw StateError('TIMEOUT');
        if (native.acquired) {
          final lease = OperationalPublicationLease._(this, native);
          _leases.add(lease);
          transferred = true;
          if (operationalNativeObservationEnabled) {
            final pause = _testAcquirePause;
            _testAcquirePause = null;
            if (pause != null) {
              await pause.hit();
              try {
                _check();
              } catch (_) {
                await lease.close();
                rethrow;
              }
            }
          }
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
    _testAcquirePause?.retire();
    _testAcquirePause = null;
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
      failed =
          failed || _failed || w.WaitForSingleObject(_poison, 0).value != 258;
      _identity.close();
      if (!w.CloseHandle(_keeper).value) failed = true;
      if (!w.CloseHandle(_poison).value) failed = true;
      if (failed) throw StateError('SERVICE_UNAVAILABLE');
    }).then(done.complete, onError: done.completeError);
    return done.future;
  }
}

final class OperationalPublicationLease {
  OperationalPublicationLease._(this._gate, this._native) {
    _done.future.ignore();
  }
  final OperationalPublicationGate _gate;
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
