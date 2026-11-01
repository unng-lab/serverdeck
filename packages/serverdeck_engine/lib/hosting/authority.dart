import 'dart:async';
import 'dart:math';

import 'package:serverdeck_protocol/validation.dart';

import '../platform/ports.dart';

/// The in-process owner identity is an object issued by one running host. There
/// is deliberately no public constructor, decoder, role field or token export.
final class OwnerCapability {
  OwnerCapability._(this._authority, this._uiBinding, this.sessionId);
  final HostAuthority _authority;
  final Object _uiBinding;
  final String sessionId;
  String get generation => _authority.generation;
  bool get isRevoked => !_authority._current(this);
  @override
  String toString() => 'OwnerCapability';
}

/// Internal composition-root authority. This library is not an RPC interface.
/// The host retains it through startup/close failures so that late platform work
/// can settle before the host releases its store or writer lease.
final class HostAuthority {
  HostAuthority._(this.runtime, this.lease, this.generation, this.clock)
    : _ownerIdentity = runtime.ownerIdentity,
      _appRoot = runtime.appRoot,
      _buildId = runtime.buildId;

  factory HostAuthority.prepare({
    required VerifiedRuntime runtime,
    required WorkspaceLease lease,
    required String generation,
    EngineClock? clock,
  }) {
    requireUuid(generation);
    final authority = HostAuthority._(
      runtime,
      lease,
      generation,
      clock ?? SystemEngineClock(),
    );
    authority._binding();
    return authority;
  }

  final VerifiedRuntime runtime;
  final WorkspaceLease lease;
  final String generation;
  final EngineClock clock;
  final String _ownerIdentity, _appRoot, _buildId;
  final _owners = Map<Object, OwnerCapability>.identity();
  final _opening = Map<Object, Completer<OwnerCapability>>.identity();
  final _proofs = <Future<void>>{};
  PublicationGate? _gate;
  Future<void>? _initializing, _initialized, _closing, _gateClosing;
  bool _ready = false, _stopping = false;
  int get ownerCount => _owners.length;
  int get pendingProofs => _proofs.length;

  /// Retained identity work can outlive a revoked issuance's logical reply.
  /// Pausing its Host never closes authority or releases its genuine lease.
  Future<void> drainProofs() async {
    while (_proofs.isNotEmpty) {
      await Future.wait<void>(_proofs.toList());
    }
  }

  bool get isStopping => _stopping;

  PublicationGate get publicationGate {
    _live();
    return _gate!;
  }

  void _binding() {
    if (!lease.isHeld ||
        lease.workspaceSlot != 'default' ||
        lease.ownerIdentity != _ownerIdentity ||
        runtime.ownerIdentity != _ownerIdentity ||
        runtime.appRoot != _appRoot ||
        runtime.buildId != _buildId ||
        _ownerIdentity.isEmpty ||
        _ownerIdentity.length > 4096 ||
        _ownerIdentity.contains('\u0000') ||
        _appRoot.isEmpty ||
        _appRoot.length > 32767 ||
        _appRoot.contains('\u0000') ||
        !RegExp(r'^[a-f0-9]{40}\+(?:Debug|Release)\+[a-f0-9]{64}$')
            .hasMatch(_buildId)) {
      throw StateError('UNAUTHORIZED');
    }
  }

  void _starting() {
    if (_stopping) throw StateError('SERVICE_UNAVAILABLE');
    try {
      _binding();
    } catch (_) {
      _stop();
      rethrow;
    }
  }

  void _live() {
    _starting();
    if (!_ready || _gate == null) throw StateError('NOT_READY');
    if (_gate!.isClosed || _gate!.generation != generation) {
      _stop();
      throw StateError('SERVICE_UNAVAILABLE');
    }
  }

  static StateError _safe(Object error) => StateError(
    error is StateError &&
            const {
              'UNAUTHORIZED',
              'FORBIDDEN',
              'TIMEOUT',
              'RESOURCE_LIMIT',
              'SERVICE_UNAVAILABLE',
              'STORAGE_BLOCKED',
              'INCOMPATIBLE',
              'PREREQUISITE_UNAVAILABLE',
            }.contains(error.message)
        ? error.message
        : 'SERVICE_UNAVAILABLE',
  );

  static Duration _budget(Duration deadline, Duration maximum) {
    if (deadline <= Duration.zero || deadline > maximum) {
      throw StateError('TIMEOUT');
    }
    return deadline;
  }

  Future<void> _proof() {
    _starting();
    if (_proofs.length >= 256) throw StateError('RESOURCE_LIMIT');
    final work = Future<void>.sync(() => runtime.revalidate(lease));
    _proofs.add(work);
    work.then<void>(
      (_) => _proofs.remove(work),
      onError: (Object _, StackTrace __) {
        _proofs.remove(work);
        // A logical timeout does not cancel a retained identity check. Its
        // eventual failure retires this generation even after the caller left.
        _stop();
      },
    );
    return work;
  }

  Future<void> initialize({Duration deadline = const Duration(seconds: 30)}) {
    _starting();
    if (_initialized != null) return _initialized!;
    final budget = _budget(deadline, const Duration(seconds: 30));
    final began = clock.elapsed;
    final work = _initializing = () async {
      try {
        await _proof();
        _starting();
        if (clock.elapsed - began >= budget) throw StateError('TIMEOUT');
        final gate = await runtime.createPublicationGate(generation, lease);
        _gate = gate;
        _starting();
        if (gate.isClosed || gate.generation != generation) {
          throw StateError('UNAUTHORIZED');
        }
        await _proof();
        _starting();
        if (clock.elapsed - began >= budget) throw StateError('TIMEOUT');
        _ready = true;
      } catch (error) {
        _stop();
        rethrow;
      }
    }();
    work.ignore();
    return _initialized = work.timeout(budget).catchError((Object error) {
      _stop();
      throw error is TimeoutException ? StateError('TIMEOUT') : _safe(error);
    });
  }

  bool _current(OwnerCapability capability) {
    try {
      _live();
      return identical(capability._authority, this) &&
          identical(_owners[capability._uiBinding], capability);
    } catch (_) {
      return false;
    }
  }

  void _requireOwner(OwnerCapability capability) {
    _live();
    if (!_current(capability)) throw StateError('UNAUTHORIZED');
  }

  Future<void> validateOwner(
    OwnerCapability capability, {
    Duration deadline = const Duration(seconds: 5),
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    _requireOwner(capability);
    final budget = _budget(deadline, const Duration(seconds: 5));
    final began = clock.elapsed;
    try {
      final actual = _proof();
      observeNativeCompletion?.call(actual);
      await actual.timeout(budget);
    } on TimeoutException {
      revokeOwner(capability);
      throw StateError('TIMEOUT');
    } catch (error) {
      if (!_isLocalRefusal(error)) _stop();
      throw _safe(error);
    }
    _requireOwner(capability);
    if (clock.elapsed - began >= budget) {
      revokeOwner(capability);
      throw StateError('TIMEOUT');
    }
  }

  /// Runtime liveness only; this cannot issue an owner or a grant capability.
  Future<void> validateRuntime({
    Duration deadline = const Duration(seconds: 5),
    void Function(Future<void>)? observeNativeCompletion,
  }) async {
    _live();
    final budget = _budget(deadline, const Duration(seconds: 5));
    final began = clock.elapsed;
    try {
      final actual = _proof();
      observeNativeCompletion?.call(actual);
      await actual.timeout(budget);
    } on TimeoutException {
      throw StateError('TIMEOUT');
    } catch (error) {
      if (!_isLocalRefusal(error)) _stop();
      throw _safe(error);
    }
    _live();
    if (clock.elapsed - began >= budget) throw StateError('TIMEOUT');
  }

  static bool _isLocalRefusal(Object error) =>
      error is StateError &&
      const {'RESOURCE_LIMIT', 'TIMEOUT'}.contains(error.message);

  Future<OwnerCapability> bindOwner(Object uiBinding) {
    _live();
    final existing = _owners[uiBinding];
    if (existing != null) {
      return validateOwner(existing).then((_) => existing);
    }
    final pending = _opening[uiBinding];
    if (pending != null) return pending.future;
    if (_owners.length + _opening.length >= 8) {
      throw StateError('RESOURCE_LIMIT');
    }
    final result = Completer<OwnerCapability>();
    result.future.ignore();
    _opening[uiBinding] = result;
    final began = clock.elapsed;
    const budget = Duration(seconds: 5);
    () async {
      try {
        try {
          await _proof().timeout(budget);
        } on TimeoutException {
          throw StateError('TIMEOUT');
        } catch (error) {
          if (!_isLocalRefusal(error)) _stop();
          rethrow;
        }
        _live();
        if (!identical(_opening[uiBinding], result)) {
          throw StateError('UNAUTHORIZED');
        }
        if (clock.elapsed - began >= budget) throw StateError('TIMEOUT');
        final capability = OwnerCapability._(this, uiBinding, _uuid());
        _owners[uiBinding] = capability;
        if (!result.isCompleted) result.complete(capability);
      } catch (error) {
        if (!result.isCompleted) result.completeError(_safe(error));
      } finally {
        if (identical(_opening[uiBinding], result)) _opening.remove(uiBinding);
      }
    }().ignore();
    return result.future;
  }

  /// Window disposal revokes both an issued identity and a pending issuance.
  /// A late proof must neither revive it nor remove a replacement binding.
  void detachOwner(Object uiBinding) {
    _owners.remove(uiBinding);
    final pending = _opening.remove(uiBinding);
    if (pending != null && !pending.isCompleted) {
      pending.completeError(StateError('UNAUTHORIZED'));
    }
  }

  void revokeOwner(OwnerCapability capability) {
    if (identical(capability._authority, this) &&
        identical(_owners[capability._uiBinding], capability)) {
      _owners.remove(capability._uiBinding);
    }
  }

  void _stop() {
    _stopping = true;
    _ready = false;
    _owners.clear();
    for (final pending in _opening.values.toList()) {
      if (!pending.isCompleted)
        pending.completeError(StateError('SERVICE_UNAVAILABLE'));
    }
    _opening.clear();
    final gate = _gate;
    if (gate != null && _gateClosing == null) {
      _gateClosing = Future<void>.sync(gate.close);
      _gateClosing!.ignore();
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _stop();
    return _closing = () async {
      try {
        await _initializing;
      } catch (_) {
        /* Readiness owns the error. */
      }
      _stop(); // A gate may have arrived after the logical close/timeout.
      try {
        await Future.wait(_proofs.toList());
      } catch (_) {
        /* Proof failure does not replace cleanup completion. */
      }
      try {
        await _gateClosing;
      } catch (_) {
        throw StateError('SERVICE_UNAVAILABLE');
      }
      // Deliberately no lease.close(): only the host can prove store closure.
    }();
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
