import 'package:serverdeck_protocol/automation/authority_owner.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';

import '../automation/authority.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

final class AutomationAuthorityOwnerApi implements TrustedOwnerApi {
  AutomationAuthorityOwnerApi(this.service);
  final TrustedAutomationAuthorityService service;
  @override
  bool supports(String method) =>
      automationAuthorityOwnerMethods.contains(method);
  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (!request.belongsTo(service.sessions) ||
        request.role != OperationalRole.owner ||
        request.method != method)
      throw StateError('FORBIDDEN');
    if (!supports(method)) throw StateError('UNSUPPORTED');
    final input = StrictCodec().decode(
      encodeMcpMessage(params, maxBytes: 256 * 1024),
      maxBytes: 256 * 1024,
    );
    AutomationAuthorityOperation? work;
    return TrustedOwnerInvocation(
      request,
      () {
        work = service.startOwner(request, method, input);
        return work!.result.then(
          (value) => value,
          onError: (Object error, StackTrace stack) {
            if (error is StateError &&
                automationAuthorityFailureCodes.contains(error.message)) {
              return <String, Object?>{
                'failure': {'code': error.message},
              };
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
      },
      onClose: () {
        work?.cancelInterest().ignore();
      },
    );
  }
}
