import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';

import '../api/operational_auth.dart';
import '../automation/jobs.dart';
import 'router.dart';

final class JobMcpServices implements TrustedMcpToolServices {
  JobMcpServices(this.service);
  final TrustedJobService service;
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

  McpToolResult _failure(Object error) => McpToolResult.failure(
    error is StateError && mcpDomainCodes.contains(error.message)
        ? error.message
        : error is FormatException
        ? 'VALIDATION'
        : 'INTERNAL',
  );
}
