import 'dart:async';

import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../profiles/mutation_coordinator.dart';
import '../remote/trust_probes.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

/// Two format3 native-owner writes using the existing common foundation queue.
final class TrustMutationOwnerApi implements TrustedOwnerApi {
  TrustMutationOwnerApi({required this.service, required this.coordinator}) {
    if (!identical(service.store, coordinator.store))
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    if (!coordinator.isTrusted) throw StateError('NOT_READY');
    _unsubscribe = service.sessions.onSessionDetached(_detach);
  }
  final HostTrustProbeService service;
  final TrustedMutationCoordinator coordinator;
  final _interests = <String, Set<String>>{};
  late final void Function() _unsubscribe;
  var _next = 0;
  bool _closed = false;
  Future<void>? _closing;

  @override
  bool supports(String method) =>
      method == 'servers.trust.confirm' || method == 'servers.trust.revoke';

  void _ready() {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    service.store.trustedOperational;
  }

  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    service.requireOwner(request, method, admitted: false);
    if (!supports(method)) throw StateError('UNSUPPORTED');
    _ready();
    requireUuid(requestId);
    final input = captureHostTrustParams(method, params);
    if (_interests.values.fold<int>(0, (n, v) => n + v.length) >= 128)
      throw StateError('RESOURCE_LIMIT');
    final session = request.sessionId;
    final interest = 'owner-trust/$session/${_next++}';
    final reservation = coordinator.reserveTrust(
      requestId,
      method,
      input,
      requester: interest,
    );
    (_interests[session] ??= {}).add(interest);
    return TrustedOwnerInvocation(request, () async {
      _ready();
      final lease = await service.sessions.beginTargetChange(
        deadline: request.rpcRemaining,
      );
      try {
        _ready();
        try {
          final budget = request.rpcRemaining;
          await request.revalidate().timeout(budget);
        } on TimeoutException {
          throw StateError('TIMEOUT');
        }
        _ready();
        request.rpcRemaining;
        final result = await coordinator.activateTrust(
          reservation,
          service,
          request,
        );
        return captureHostTrustResult(method, result.toJson());
      } finally {
        await lease.close();
      }
    }, onClose: () => _release(session, interest));
  }

  void _release(String session, String interest) {
    final interests = _interests[session];
    if (interests == null || !interests.remove(interest)) return;
    if (interests.isEmpty) _interests.remove(session);
    coordinator.detach(interest);
  }

  void _detach(String session) {
    final interests = _interests.remove(session);
    if (interests != null) {
      for (final interest in interests) {
        coordinator.detach(interest);
      }
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    _unsubscribe();
    for (final session in _interests.keys.toList()) {
      _detach(session);
    }
    return _closing = coordinator.close();
  }
}
