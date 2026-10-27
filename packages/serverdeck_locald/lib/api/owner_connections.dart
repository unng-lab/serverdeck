import 'package:serverdeck_protocol/connections.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../remote/connections.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

final class ConnectionOwnerApi implements TrustedOwnerApi {
  ConnectionOwnerApi(this.service);
  final TrustedConnectionService service;
  @override
  bool supports(String method) => connectionOwnerMethods.contains(method);
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
    final input = captureConnectionParams(method, params);
    if (method == 'servers.connect') {
      final reservation = service.reserve(request, input, requestId);
      return TrustedOwnerInvocation(
        request,
        () async => captureConnectionResult(
          method,
          service.startOwner(request, reservation),
        ),
        onClose: () => service.release(reservation),
      );
    }
    return TrustedOwnerInvocation(request, () async {
      final result = switch (method) {
        'servers.connection' => await service.viewOwner(
          request,
          input['profileId'] as String,
        ),
        'servers.disconnect' => await service.viewOwner(
          request,
          input['profileId'] as String,
          disconnect: true,
        ),
        'servers.connectStatus' => await service.ownerStatus(
          request,
          input['operationId'] as String,
        ),
        'servers.connectCancel' => await service.ownerStatus(
          request,
          input['operationId'] as String,
          cancel: true,
        ),
        _ => throw StateError('UNSUPPORTED'),
      };
      return captureConnectionResult(method, result);
    });
  }
}
