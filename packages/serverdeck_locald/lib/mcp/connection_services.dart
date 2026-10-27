import 'dart:async';

import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../remote/connections.dart';
import '../remote/reads.dart' show remoteReadTools;
import '../automation/plans.dart' show planTools;
import '../automation/jobs.dart' show jobTools;
import 'router.dart';

final class ConnectionMcpServices implements TrustedMcpToolServices {
  ConnectionMcpServices(this.service);
  final TrustedConnectionService service;
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    try {
      if (!context.belongsTo(service.sessions, service.authority))
        throw StateError('FORBIDDEN');
      if (tool.name != 'serverdeck_server_connect' &&
          tool.name != 'serverdeck_server_disconnect')
        throw StateError('UNSUPPORTED');
      requireFields(arguments, {'serverId'});
      final id = requireUuid(arguments['serverId']);
      final work = tool.name == 'serverdeck_server_connect'
          ? service.connectMcp(context, id)
          : service.disconnectMcp(context, id);
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
    final code = error is TimeoutException
        ? 'TIMEOUT'
        : error is FormatException
        ? 'VALIDATION'
        : error is StateError && TrustedLocalError.codes.contains(error.message)
        ? error.message
        : 'INTERNAL';
    return McpToolResult.failure(
      code,
      boundary: error is ConnectionServiceFailure ? error.boundary : 'local',
      retry: const {'SERVICE_UNAVAILABLE', 'TIMEOUT'}.contains(code)
          ? 'reconnect'
          : 'none',
    );
  }
}

/// Closed dispatch: implementations explicitly own a disjoint set of tools.
final class TrustedMcpServiceGroup implements TrustedMcpToolServices {
  TrustedMcpServiceGroup({
    required this.catalog,
    required this.connections,
    required this.reads,
    required this.plans,
    required this.automationAuthority,
    required this.jobs,
  });
  final TrustedMcpToolServices catalog,
      connections,
      reads,
      plans,
      automationAuthority,
      jobs;
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    if (jobTools.contains(tool.name))
      return jobs.start(context, tool, arguments);
    if (tool.name == 'serverdeck_approval_request')
      return automationAuthority.start(context, tool, arguments);
    if (planTools.contains(tool.name))
      return plans.start(context, tool, arguments);
    if (remoteReadTools.contains(tool.name))
      return reads.start(context, tool, arguments);
    if (tool.name.startsWith('serverdeck_profiles_'))
      return catalog.start(context, tool, arguments);
    if (tool.name == 'serverdeck_server_connect' ||
        tool.name == 'serverdeck_server_disconnect')
      return connections.start(context, tool, arguments);
    return McpServiceOperation(
      Future.value(McpToolResult.failure('UNSUPPORTED')),
      () async {},
    );
  }
}
