import 'dart:async';

import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/errors.dart';

import '../api/operational_auth.dart';
import '../automation/profiles.dart';
import 'router.dart';

/// The actual seven author tools, sharing the exact owner catalog backend.
/// Other domains remain unavailable until their concrete services are installed.
final class ProfileCatalogMcpServices implements McpToolServices {
  ProfileCatalogMcpServices(this.service);
  final AutomationProfileService service;
  @override
  McpServiceOperation start(
    OperationalMcpContext context,
    McpToolDefinition tool,
    Map<String, Object?> arguments,
  ) {
    ProfileCatalogOperation? work;
    try {
      if (!context.belongsTo(service.sessions, service.authority))
        throw StateError('FORBIDDEN');
      const prefix = 'serverdeck_profiles_';
      if (!tool.name.startsWith(prefix)) throw StateError('UNSUPPORTED');
      final operation = tool.name.substring(prefix.length);
      if (!profileCatalogOperations.contains(operation))
        throw StateError('UNSUPPORTED');
      final actor = service.mcpActor(context, operation);
      final input = ProfileCatalogInput.capture(operation, arguments);
      work = service.start(actor, input);
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
    var code = error is FormatException
        ? 'VALIDATION'
        : error is TimeoutException
        ? 'TIMEOUT'
        : 'INTERNAL';
    if (error is StateError && mcpDomainCodes.contains(error.message))
      code = error.message;
    final known = ErrorCode.values
        .where((value) => value.wireName == code)
        .firstOrNull;
    return McpToolResult.failure(
      code,
      retry: known == null
          ? 'none'
          : LocalError(known).toJson()['retry'] as String,
    );
  }
}
