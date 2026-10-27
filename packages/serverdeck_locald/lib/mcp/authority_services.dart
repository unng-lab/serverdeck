import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';

import '../api/operational_auth.dart';
import '../automation/authority.dart';
import 'router.dart';

/// AI may request an exact plan's consent. It cannot decide or delegate rights.
final class AutomationAuthorityMcpServices implements TrustedMcpToolServices {
  AutomationAuthorityMcpServices(this.service);
  final TrustedAutomationAuthorityService service;
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    try {
      if (tool.name != 'serverdeck_approval_request')
        throw StateError('UNSUPPORTED');
      validateMcpArguments(tool, arguments);
      final work = service.startMcp(context, arguments);
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
