import 'dart:async';

import 'package:serverdeck_protocol/protocol.dart' show rpcDeadline;
import 'package:serverdeck_protocol/validation.dart';

import '../platform/ports.dart';

/// Internal mutation ordering, not a permission or a wire-accessible service.
/// The composition root supplies retirement of its own session registry.
final class TargetChanges {
  TargetChanges({
    required this.gate,
    required bool Function() isStopping,
    required void Function(Set<String>? affected) retireMcp,
    required void Function() onFailure,
    EngineClock? clock,
  }) : _isStopping = isStopping,
       _retireMcp = retireMcp,
       _onFailure = onFailure,
       _clock = clock ?? SystemEngineClock();

  final PublicationGate gate;
  final bool Function() _isStopping;
  final void Function(Set<String>?) _retireMcp;
  final void Function() _onFailure;
  final EngineClock _clock;
  final _interests = <_TargetChangeInterest>{};
  final _authority = <Future<void>>{};
  bool _stopped = false;
  bool _failed = false;
  Future<void>? _closing;
  Future<void>? _gateClosing;
  int get interests => _interests.length;
  bool get isStopping => _stopped || _isStopping();

  void _live() {
    if (isStopping || gate.isClosed) throw StateError('SERVICE_UNAVAILABLE');
  }

  void _retire(Set<String>? affected) {
    if (_failed) throw StateError('SERVICE_UNAVAILABLE');
    try {
      _retireMcp(affected);
    } catch (_) {
      _fail();
      throw StateError('SERVICE_UNAVAILABLE');
    }
  }

  void _fail() {
    if (_failed) return;
    _failed = true;
    stop();
    try {
      _onFailure();
    } catch (_) {
      /* Intake is already closed. */
    }
  }

  Future<T> runAuthority<T>(
    Future<T> Function() effect,
    Duration deadline, {
    void Function(Future<void>)? observeNativeCompletion,
  }) {
    try {
      _live();
      if (_authority.length + _interests.length >= 16)
        throw StateError('RESOURCE_LIMIT');
    } catch (error, stack) {
      return Future.error(error, stack);
    }
    final reply = Completer<T>();
    reply.future.ignore();
    final done = Completer<void>();
    _authority.add(done.future);
    _runAuthority(effect, deadline, observeNativeCompletion, reply)
        .then<void>(
          (value) {
            if (!reply.isCompleted) reply.complete(value);
          },
          onError: (Object error, StackTrace stack) {
            if (!reply.isCompleted) reply.completeError(error, stack);
          },
        )
        .whenComplete(() {
          _authority.remove(done.future);
          done.complete();
        })
        .ignore();
    return reply.future;
  }

  Future<T> _runAuthority<T>(
    Future<T> Function() effect,
    Duration deadline,
    void Function(Future<void>)? observer,
    Completer<T> reply,
  ) async {
    if (deadline <= Duration.zero) throw StateError('TIMEOUT');
    final budget = deadline < rpcDeadline ? deadline : rpcDeadline;
    final began = _clock.elapsed;
    PublicationLease? lease;
    final acquiring = gate.beginAcquire(deadline: budget);
    var observerFailed = false;
    try {
      observer?.call(acquiring.settled);
    } catch (_) {
      observerFailed = true;
    }
    try {
      lease = await acquiring.result;
      try {
        observer?.call(lease.done);
      } catch (_) {
        observerFailed = true;
      }
      if (observerFailed) throw StateError('SERVICE_UNAVAILABLE');
      if (_clock.elapsed - began >= budget) throw StateError('TIMEOUT');
      _live();
      return await effect();
    } catch (error, stack) {
      if (!reply.isCompleted)
        reply.completeError(
          observerFailed ? StateError('SERVICE_UNAVAILABLE') : error,
          stack,
        );
      if (observerFailed) throw StateError('SERVICE_UNAVAILABLE');
      rethrow;
    } finally {
      try {
        try {
          await lease?.close();
        } finally {
          await acquiring.settled;
        }
      } catch (_) {
        _fail();
        throw StateError('SERVICE_UNAVAILABLE');
      }
    }
  }

  Future<TargetChangeLease> begin(Duration deadline) =>
      _begin(deadline, reconciled: false);

  Future<ReconciledTargetChangeLease> beginReconciled(Duration deadline) =>
      _begin(
        deadline,
        reconciled: true,
      ).then((lease) => ReconciledTargetChangeLease._(lease._interest));

  Future<TargetChangeLease> _begin(
    Duration deadline, {
    required bool reconciled,
  }) {
    try {
      _live();
      if (deadline <= Duration.zero) throw StateError('TIMEOUT');
      if (_interests.length + _authority.length >= 16)
        throw StateError('RESOURCE_LIMIT');
      final interest = _TargetChangeInterest(
        this,
        deadline < rpcDeadline ? deadline : rpcDeadline,
        reconciled: reconciled,
      );
      _interests.add(interest);
      interest.run().ignore();
      return interest.result.future;
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  void _finish(_TargetChangeInterest interest) {
    _interests.remove(interest);
    if (!interest.done.isCompleted) interest.done.complete();
  }

  void stop() {
    _stopped = true;
    _gateClosing ??= Future<void>.sync(gate.close);
    _gateClosing!.ignore();
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    stop();
    return _closing =
        Future.wait<void>([
          _gateClosing!,
          ..._authority.toList(),
          for (final interest in _interests.toList()) interest.done.future,
        ]).then<void>((_) {
          if (_failed) throw StateError('SERVICE_UNAVAILABLE');
        });
  }
}

final class _TargetChangeInterest {
  _TargetChangeInterest(this.owner, this.budget, {required this.reconciled})
    : began = owner._clock.elapsed {
    result.future.ignore();
    done.future.ignore();
  }
  final TargetChanges owner;
  final Duration budget, began;
  final bool reconciled;
  final result = Completer<TargetChangeLease>();
  final done = Completer<void>();
  PublicationLease? native;
  Future<void>? _releaseFuture;

  Future<void> run() async {
    var transferred = false;
    PublicationAcquisition? acquiring;
    try {
      acquiring = owner.gate.beginAcquire(deadline: budget);
      native = await acquiring.result;
      if (owner._clock.elapsed - began >= budget) throw StateError('TIMEOUT');
      owner._live();
      if (!reconciled) owner._retire(null);
      if (owner._clock.elapsed - began >= budget) throw StateError('TIMEOUT');
      owner._live();
      result.complete(TargetChangeLease._(this));
      transferred = true;
    } catch (error) {
      final code =
          error is StateError &&
              const {
                'TIMEOUT',
                'RESOURCE_LIMIT',
                'UNAUTHORIZED',
                'SERVICE_UNAVAILABLE',
              }.contains(error.message)
          ? error.message
          : 'SERVICE_UNAVAILABLE';
      result.completeError(StateError(code));
      try {
        try {
          await acquiring?.settled;
          if (!reconciled) owner._retire(null);
        } finally {
          await native?.close();
        }
      } catch (_) {
        owner._fail();
      }
    } finally {
      if (!transferred) owner._finish(this);
    }
  }

  Future<void> release() => _releaseFuture ??= () async {
    try {
      await native!.close();
    } catch (_) {
      owner._fail();
      throw StateError('SERVICE_UNAVAILABLE');
    } finally {
      owner._finish(this);
    }
  }();
}

/// Opaque, idempotent ownership held until the actual mutation/invalidation ends.
final class TargetChangeLease {
  TargetChangeLease._(this._interest);
  final _TargetChangeInterest _interest;
  Future<void> close() => _interest.release();
}

final class ReconciledTargetChangeLease {
  ReconciledTargetChangeLease._(this._interest);
  final _TargetChangeInterest _interest;
  void _live() {
    if (!_interest.reconciled ||
        _interest.native == null ||
        _interest._releaseFuture != null)
      throw StateError('SERVICE_UNAVAILABLE');
  }

  void retireAffected(Set<String> profileIds) {
    _live();
    if (profileIds.length > 250) throw StateError('RESOURCE_LIMIT');
    for (final id in profileIds) requireUuid(id);
    if (profileIds.isEmpty) return;
    _interest.owner._retire(Set.unmodifiable(profileIds));
  }

  void retireAll() {
    _live();
    _interest.owner._retire(null);
  }

  Future<void> close() => _interest.release();
}
