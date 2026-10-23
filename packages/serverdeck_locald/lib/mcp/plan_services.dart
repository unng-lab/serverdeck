import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';

import '../api/operational_auth.dart';
import '../automation/plans.dart';
import 'router.dart';

final class PlanMcpServices implements TrustedMcpToolServices {
  PlanMcpServices(this.service);
  final TrustedPlanService service;
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    try {
      final work = service.startMcp(context, tool.name, arguments);
      return McpServiceOperation(
        work.result.then(
          McpToolResult.success,
          onError: (Object error, StackTrace _) => _failure(error),
        ),
        work.cancelInterest,
      );
    } catch (error) {
      return McpServiceOperation(Future.value(_failure(error)), () async {});
    }
  }

  McpToolResult _failure(Object error) {
    final code = error is StateError && mcpDomainCodes.contains(error.message)
        ? error.message
        : error is FormatException || error is McpProtocolException
        ? 'VALIDATION'
        : 'INTERNAL';
    return McpToolResult.failure(
      code,
      retry:
          const {
            'IDEMPOTENCY_CONFLICT',
            'PLAN_STALE',
            'PLAN_EXPIRED',
            'REVISION_CONFLICT',
          }.contains(code)
          ? 'reload'
          : 'none',
    );
  }
}
