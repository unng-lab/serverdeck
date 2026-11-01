import 'package:serverdeck_protocol/mcp/handshake.dart';

import '../hosting/sessions.dart';

/// Owner adapters use the common coordinator; they cannot mint a role.
abstract interface class TrustedOwnerApi {
  bool supports(String method);
  TrustedOwnerInvocation prepare(
    SessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  });
}

/// Prepared by trusted engine adapters; execution checks admitted owner identity.
/// Wire input cannot supply a role, callback or invocation token.
final class TrustedOwnerInvocation extends _OwnerInvocation {
  TrustedOwnerInvocation(this.request, super.effect, {super.onClose});
  final SessionRequest request;
  @override
  void _guard() {
    if (!request.initialAdmissionProved ||
        request.role != OperationalRole.owner)
      throw StateError('FORBIDDEN');
    request.rpcRemaining;
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
    SessionRequest request,
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
