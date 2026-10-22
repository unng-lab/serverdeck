import 'package:serverdeck_protocol/mcp/handshake.dart';

import 'operational_auth.dart';

/// Trusted owner adapters use the common coordinator; they cannot mint a role.
abstract interface class OperationalOwnerApi {
  bool supports(String method);
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  });
}

/// Prepared by trusted adapter code after the retained native role gate; no
/// callback, role or invocation token can be supplied through a wire payload.
final class OperationalOwnerInvocation extends _OwnerInvocation {
  OperationalOwnerInvocation(this.request, super.effect, {super.onClose});
  final OperationalSessionRequest request;
  @override
  void _guard() {
    if (!request.initialAdmissionProved ||
        request.role != OperationalRole.owner)
      throw StateError('FORBIDDEN');
    request.rpcRemaining;
  }
}

extension OperationalOwnerDispatch on OperationalOwnerApi {
  Future<Map<String, Object?>> dispatch(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) async {
    if (!request.initialAdmissionProved) throw StateError('FORBIDDEN');
    final invocation = prepare(request, method, params, requestId: requestId);
    try {
      return await invocation.execute();
    } finally {
      invocation.close();
    }
  }
}

final class OperationalOwnerApiGroup implements OperationalOwnerApi {
  OperationalOwnerApiGroup(Iterable<OperationalOwnerApi> adapters)
    : _adapters = List.unmodifiable(adapters);
  final List<OperationalOwnerApi> _adapters;
  @override
  bool supports(String method) => _adapters.any((a) => a.supports(method));
  @override
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (request.role != OperationalRole.owner || request.method != method)
      throw StateError('FORBIDDEN');
    final matches = _adapters.where((a) => a.supports(method)).toList();
    if (matches.isEmpty) throw StateError('UNSUPPORTED');
    if (matches.length != 1) throw StateError('INTERNAL');
    return matches.single.prepare(
      request,
      method,
      params,
      requestId: requestId,
    );
  }
}

/// Trusted owner adapters use the common coordinator; they cannot mint a role.
abstract interface class TrustedOwnerApi {
  bool supports(String method);
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  });
}

/// Prepared by trusted adapter code after the retained native role gate; no
/// callback, role or invocation token can be supplied through a wire payload.
final class TrustedOwnerInvocation extends _OwnerInvocation {
  TrustedOwnerInvocation(this.request, super.effect, {super.onClose});
  final TrustedSessionRequest request;
  @override
  void _guard() {
    if (!request.initialAdmissionProved ||
        request.role != OperationalRole.owner)
      throw StateError('FORBIDDEN');
    request.rpcRemaining;
  }
}

extension TrustedOwnerDispatch on TrustedOwnerApi {
  Future<Map<String, Object?>> dispatch(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) async {
    if (!request.initialAdmissionProved) throw StateError('FORBIDDEN');
    final invocation = prepare(request, method, params, requestId: requestId);
    try {
      return await invocation.execute();
    } finally {
      invocation.close();
    }
  }
}

final class TrustedOwnerApiGroup implements TrustedOwnerApi {
  TrustedOwnerApiGroup(Iterable<TrustedOwnerApi> adapters)
    : _adapters = List.unmodifiable(adapters);
  final List<TrustedOwnerApi> _adapters;
  @override
  bool supports(String method) => _adapters.any((a) => a.supports(method));
  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (request.role != OperationalRole.owner || request.method != method)
      throw StateError('FORBIDDEN');
    final matches = _adapters.where((a) => a.supports(method)).toList();
    if (matches.isEmpty) throw StateError('UNSUPPORTED');
    if (matches.length != 1) throw StateError('INTERNAL');
    return matches.single.prepare(
      request,
      method,
      params,
      requestId: requestId,
    );
  }
}

sealed class _OwnerInvocation {
  _OwnerInvocation(this._effect, {void Function()? onClose})
    : _onClose = onClose;
  final Future<Map<String, Object?>> Function() _effect;
  final void Function()? _onClose;
  Future<Map<String, Object?>>? _work;
  bool _closed = false;
  void _guard();
  Future<Map<String, Object?>> execute() {
    try {
      if (_closed) throw StateError('SERVICE_UNAVAILABLE');
      _guard();
      return _work ??= Future.sync(_effect);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _onClose?.call();
  }
}
