import 'package:serverdeck_protocol/mcp/handshake.dart';

import '../automation/profiles.dart';
import 'operational_auth.dart';
import 'operational_server.dart';

/// Owner adapter for automation content; foundation profiles.* are connections.
final class OperationalProfileOwnerApi implements OperationalOwnerApi {
  OperationalProfileOwnerApi(this.service);
  final AutomationProfileService service;
  bool _closed = false;
  String? _operation(String method) {
    const prefix = 'automation.profiles.';
    if (!method.startsWith(prefix)) return null;
    final operation = method.substring(prefix.length);
    return profileCatalogOperations.contains(operation) ? operation : null;
  }

  @override
  bool supports(String method) => _operation(method) != null;
  @override
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!request.belongsTo(service.sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method) {
      throw StateError('FORBIDDEN');
    }
    if (_closed) throw StateError('NOT_READY');
    final operation = _operation(method);
    if (operation == null) throw StateError('UNSUPPORTED');
    // Capture before initial native proof without reading results or effects.
    final input = ProfileCatalogInput.parse(operation, params);
    ProfileCatalogOperation? work;
    return OperationalOwnerInvocation(
      request,
      () {
        if (_closed) throw StateError('NOT_READY');
        final actor = service.ownerActor(request, operation);
        work = service.start(actor, input);
        return work!.result;
      },
      onClose: () {
        work?.cancelInterest();
      },
    );
  }

  void close() {
    _closed = true;
  }
}
