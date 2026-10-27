import '../codec.dart';
import '../mcp/operations.dart';
import '../mcp/wire.dart';
import '../validation.dart';

const ownerAutomationStartMethods = {
  'plans.create',
  'plans.get',
  'jobs.apply',
  'jobs.list',
  'jobs.get',
  'jobs.events',
  'jobs.cancel',
  'jobs.reconcile',
};
const ownerAutomationInlineMethods = {
  'plans.get',
  'jobs.list',
  'jobs.get',
  'jobs.events',
};
const ownerAutomationMethods = {
  ...ownerAutomationStartMethods,
  'automation.status',
  'automation.cancel',
};

/// Native owner handle framing uses the same bounded business-result envelope
/// as MCP, without granting an MCP role or routing owner requests through it.
Map<String, Object?> captureOwnerAutomationResult(
  String method,
  Map<String, Object?> input,
) {
  final value = StrictCodec().decode(
    encodeMcpMessage(input, maxBytes: 2 * 1024 * 1024),
    maxBytes: 2 * 1024 * 1024,
  );
  if (!ownerAutomationMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  requireUuid(value['operationId']);
  if (method == 'automation.cancel') {
    requireFields(value, {'operationId', 'cancelled'});
    if (value['cancelled'] is! bool) throw const FormatException('VALIDATION');
  } else if (value['state'] == 'running') {
    if (ownerAutomationInlineMethods.contains(method))
      throw const FormatException('VALIDATION');
    requireFields(value, {'operationId', 'state'});
  } else if ((method == 'automation.status' ||
          ownerAutomationInlineMethods.contains(method)) &&
      value['state'] == 'done') {
    requireFields(value, {'operationId', 'state', 'kind', 'result'});
    if (!ownerAutomationStartMethods.contains(value['kind']))
      throw const FormatException('VALIDATION');
    if (method != 'automation.status' && value['kind'] != method)
      throw const FormatException('VALIDATION');
    value['result'] = McpToolResult.fromJson(value['result']).toJson();
  } else {
    throw const FormatException('VALIDATION');
  }
  return _freeze(value) as Map<String, Object?>;
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?> value => Map<String, Object?>.unmodifiable({
    for (final entry in value.entries) entry.key: _freeze(entry.value),
  }),
  List value => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
