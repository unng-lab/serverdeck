import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../remote/trust_probes.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

final class TrustProbeOwnerApi implements TrustedOwnerApi {
  TrustProbeOwnerApi(this.service);
  final HostTrustProbeService service;
  static const _methods = {
    'servers.trust.get',
    'servers.trust.probe',
    'servers.trust.probeStatus',
    'servers.trust.probeCancel',
  };
  @override
  bool supports(String method) => _methods.contains(method);
  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    service.requireOwner(request, method, admitted: false);
    if (!supports(method)) throw StateError('UNSUPPORTED');
    requireUuid(requestId);
    final input = captureHostTrustParams(method, params);
    if (method == 'servers.trust.probe') {
      final reservation = service.reserve(request, input, requestId);
      return TrustedOwnerInvocation(
        request,
        () async => service.start(request, reservation),
        onClose: () => service.release(reservation),
      );
    }
    return TrustedOwnerInvocation(request, () async {
      await request.revalidate();
      request.rpcRemaining;
      final result = switch (method) {
        'servers.trust.get' => service.get(request, input),
        'servers.trust.probeStatus' => service.status(request, input),
        'servers.trust.probeCancel' => service.cancel(request, input),
        _ => throw StateError('UNSUPPORTED'),
      };
      return captureHostTrustResult(method, result);
    });
  }
}
