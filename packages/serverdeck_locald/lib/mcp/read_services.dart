import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';

import '../api/operational_auth.dart';
import '../remote/reads.dart';
import 'router.dart';

final class RemoteReadMcpServices implements TrustedMcpToolServices {
  RemoteReadMcpServices(this.service);
  final RemoteReadService service;
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
        : error is FormatException
        ? 'VALIDATION'
        : 'INTERNAL';
    return McpToolResult.failure(
      code,
      retry: code == 'CURSOR_EXPIRED'
          ? 'reload'
          : const {'NOT_READY', 'SERVICE_UNAVAILABLE', 'TIMEOUT'}.contains(code)
          ? 'reconnect'
          : 'none',
    );
  }
}
