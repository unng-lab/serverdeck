import 'dart:async';
import 'dart:developer' show Timeline;
import 'dart:isolate';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/owner_api.dart';
import 'sessions.dart';

part 'worker_gateway.dart';

abstract interface class EngineGateway {
  String get generation;
  bool get isClosed;

  /// Logical response-interest retirement, not proof of native cleanup.
  Future<void> get retired;
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  });
  Future<void> close();
}

/// Response interest and actual dispatch/proof/cleanup completion are separate.
/// Only the trusted worker binding uses this handle; no authority is exported.
final class EngineInvocation {
  EngineInvocation._(this.result, this.settled) {
    result.ignore();
    settled.ignore();
  }
  final Future<Map<String, Object?>> result;
  final Future<void> settled;
}

/// Same fixed public errors as typed owner dispatch; provider diagnostics and
/// input/credentials are deliberately absent from the exception.
final class EngineCallFailure implements Exception {
  EngineCallFailure(String code, {String? field})
    : _error = TrustedLocalError(code, field: field);
  final TrustedLocalError _error;
  String get code => _error.code;
  String? get field => _error.field;
  RetryAdvice get retry => _error.retry;
  Map<String, Object?> toJson() => _error.toJson();
  @override
  String toString() => 'EngineCallFailure($code)';
}

/// Bound by the Host to one opaque local owner session and its actual services.
/// It has no transport, owner token, role selector, reconnect or retry path.
final class InProcessGateway implements EngineGateway {
  InProcessGateway({
    required OwnerSession owner,
    required TrustedOwnerApi services,
    required TrustedReadiness Function() readiness,
  }) : _owner = owner,
       _services = services,
       _readiness = readiness {
    if (!owner.isCurrent) throw EngineCallFailure('UNAUTHORIZED');
  }
  final OwnerSession _owner;
  final TrustedOwnerApi _services;
  final TrustedReadiness Function() _readiness;
  final _active = <Future<void>>{};
  final _retired = Completer<void>();
  @override
  Future<void> get retired => _retired.future;
  bool _closed = false, _closeFailed = false;
  Future<void>? _closing;
  @override
  String get generation => _owner.generation;
  @override
  bool get isClosed => _closed || !_owner.isCurrent;

  static EngineCallFailure _safe(Object error) {
    if (error is EngineCallFailure) return error;
    if (error is TimeoutException) return EngineCallFailure('TIMEOUT');
    if (error is FormatException) return EngineCallFailure('VALIDATION');
    if (error is SshTransportFailure)
      return EngineCallFailure(
        TrustedLocalError.fromTransport(error.code).code,
      );
    if (error is StateError && TrustedLocalError.codes.contains(error.message))
      return EngineCallFailure(error.message);
    return EngineCallFailure('INTERNAL');
  }

  void _live() {
    if (_closed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    if (!_owner.isCurrent) throw EngineCallFailure('UNAUTHORIZED');
  }

  TrustedReadiness _view() {
    final view = _readiness();
    if (view.generation != generation) throw EngineCallFailure('INTERNAL');
    return view;
  }

  void _domainReady() {
    final view = _view();
    if (view.state != ReadinessState.ready)
      throw EngineCallFailure(view.toJson()['reason'] as String);
  }

  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) => beginCall(method, params, requestId: requestId).result;

  /// [expiresAt] is an absolute deadline in this owner's registry clock domain.
  /// A trusted worker uses the shared VM monotonic epoch; ordinary calls use
  /// the existing five-second reservation. No queue hop can extend that budget.
  EngineInvocation beginCall(
    String method,
    Map<String, Object?> params, {
    required String requestId,
    Duration? expiresAt,
  }) {
    SessionRequest? request;
    Completer<void>? physical;
    try {
      _live();
      // Identity/method gate precedes payload capture or service lookup.
      request = _owner.reserve(method, expiresAt: expiresAt);
      physical = Completer<void>();
      final actual = physical.future;
      _active.add(actual);
      actual.then<void>(
        (_) => _active.remove(actual),
        onError: (Object _, StackTrace __) {
          _active.remove(actual);
          _closeFailed = true;
        },
      );
      final input = _captureGatewayInput(method, params, requestId);
      final reply = Completer<Map<String, Object?>>();
      reply.future.ignore();
      // This is the original reservation budget, including preparation time.
      final responding = reply.future.timeout(request.rpcBudgetRemaining);
      final admitted = request;
      final completion = physical;
      Future<void>.sync(
        () => _dispatch(admitted, method, input, requestId, reply),
      ).then<void>(
        completion.complete,
        onError: (Object error, StackTrace _) =>
            completion.completeError(_safe(error)),
      );
      return EngineInvocation._(
        responding.catchError((Object error) {
          throw _safe(error);
        }),
        actual,
      );
    } catch (error) {
      request?.complete();
      final drain = request?.settled ?? Future<void>.value();
      final completion = physical;
      if (completion != null) {
        drain.then<void>(
          completion.complete,
          onError: (Object _, StackTrace __) => completion.completeError(
            EngineCallFailure('SERVICE_UNAVAILABLE'),
          ),
        );
      }
      return EngineInvocation._(
        Future.error(_safe(error)),
        physical?.future ?? drain,
      );
    }
  }

  Future<void> _dispatch(
    SessionRequest request,
    String method,
    Map<String, Object?> input,
    String requestId,
    Completer<Map<String, Object?>> reply,
  ) async {
    TrustedOwnerInvocation? invocation;
    var closeAfter = false;
    try {
      final builtin = const {
        'readiness.get',
        'session.ping',
        'session.close',
      }.contains(method);
      if (builtin) {
        requireFields(input, {});
      } else {
        _domainReady();
        if (!_services.supports(method)) throw EngineCallFailure('UNSUPPORTED');
        invocation = _services.prepare(
          request,
          method,
          input,
          requestId: requestId,
        );
      }
      await _owner.admit(request);
      _live();
      request.rpcRemaining;
      late Map<String, Object?> result;
      switch (method) {
        case 'readiness.get':
          result = _view().toJson();
        case 'session.ping':
          result = {'leaseSeconds': 60};
        case 'session.close':
          result = {'closed': true};
          closeAfter = true;
        default:
          _domainReady();
          result = await invocation!.execute();
      }
      // Same bounded JSON projection as the previous typed server, captured
      // before the final await so later mutation cannot change a delivered DTO.
      final captured = _capture(result, requestId);
      _closeInvocation(invocation);
      invocation = null;
      _live();
      final remaining = request.rpcBudgetRemaining;
      await request.revalidate().timeout(remaining);
      _live();
      request.rpcRemaining;
      if (!builtin) _domainReady();
      if (closeAfter) _retire();
      if (!reply.isCompleted) reply.complete(captured);
    } catch (error) {
      if (!reply.isCompleted)
        reply.completeError(
          _closed && !closeAfter
              ? EngineCallFailure('SERVICE_UNAVAILABLE')
              : _safe(error),
        );
    } finally {
      try {
        _closeInvocation(invocation);
      } catch (_) {
        _closeFailed = true;
      }
      request.complete();
      await request.settled;
      if (_closeFailed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    }
  }

  Map<String, Object?> _capture(Map<String, Object?> result, String requestId) {
    try {
      final bytes = encodeMcpMessage({
        'v': 1,
        'id': requestId,
        'generation': generation,
        'result': result,
      }, maxBytes: maxResponseBytes);
      final detached = StrictCodec().decode(
        bytes,
        maxBytes: maxResponseBytes,
      )['result'];
      return _freezeGateway(detached) as Map<String, Object?>;
    } catch (_) {
      throw EngineCallFailure('INTERNAL');
    }
  }

  void _closeInvocation(TrustedOwnerInvocation? invocation) {
    try {
      invocation?.close();
    } catch (_) {
      _closeFailed = true;
      try {
        _retire();
      } catch (_) {
        /* Preserve failed cleanup state. */
      }
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    }
  }

  void _retire() {
    if (_closed) return;
    _closed = true;
    _retired.complete();
    try {
      _owner.close();
    } catch (_) {
      _closeFailed = true;
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    }
  }

  @override
  Future<void> close() {
    if (_closing != null) return _closing!;
    try {
      _retire();
    } catch (_) {
      _closeFailed = true;
    }
    return _closing = Future.wait<void>(_active.toList()).then((_) {
      if (_closeFailed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    });
  }
}

Map<String, Object?> _captureGatewayInput(
  String method,
  Map<String, Object?> params,
  String requestId,
) {
  requireUuid(requestId);
  if (method.isEmpty || method.runes.length > 256)
    throw const FormatException('VALIDATION');
  // Preserve the former whole-envelope byte/depth budget. The nonce here
  // is only a constant sizing placeholder, never an owner credential.
  late List<int> encoded;
  try {
    encoded = encodeMcpMessage({
      'v': 1,
      'id': requestId,
      'sessionId': 'A' * 43,
      'method': method,
      'params': params,
    }, maxBytes: maxRequestBytes);
  } on McpProtocolException {
    throw const FormatException('VALIDATION');
  }
  late Map<String, Object?> input;
  try {
    input =
        StrictCodec().decode(encoded, maxBytes: maxRequestBytes)['params']
            as Map<String, Object?>;
  } finally {
    encoded.fillRange(0, encoded.length, 0);
  }
  return input;
}
