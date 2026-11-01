import 'package:serverdeck_protocol/discovery.dart';

/// Namespace is bound to the actual worker SID, never a caller-selected root.
Future<void> requireEmbeddedEndpoint(String name, String actualSid) async {
  final names = (await DiscoveryNamespace.forOwner(actualSid)).pipeNames;
  if (!names.contains(name)) throw StateError('UNAUTHORIZED');
}

Duration remainingPipeBudget(int expiresAt, int now) =>
    _remaining(expiresAt, now, 5000000);
Duration remainingPipeReadBudget(int expiresAt, int now) =>
    _remaining(expiresAt, now, 60000000);
Duration _remaining(int expiresAt, int now, int maximum) {
  final remaining = expiresAt - now;
  if (remaining <= 0) throw StateError('TIMEOUT');
  if (remaining > maximum) throw StateError('VALIDATION');
  return Duration(microseconds: remaining);
}

void requireEmbeddedPeerPid(int value) {
  if (value < 1 || value > 0xffffffff) throw StateError('VALIDATION');
}

/// MS-FSCC FilePipeLocalInformation uses different write quotas at each end.
bool embeddedPipeOutputEmpty(
  List<int> fields, {
  required bool server,
  required bool writing,
}) {
  if (fields.length != 10 ||
      fields.any((v) => v < 0 || v > 0xffffffff) ||
      fields[8] != 3 ||
      fields[9] != (server ? 1 : 0))
    throw StateError('SERVICE_UNAVAILABLE');
  final capacity = fields[server ? 6 : 4], available = fields[7];
  if (available > capacity) throw StateError('SERVICE_UNAVAILABLE');
  return available == capacity && !writing;
}
