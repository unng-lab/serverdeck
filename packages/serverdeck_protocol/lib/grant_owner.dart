import 'automation/models.dart'
    show GrantScopePolicy, requireAutomationRevision;
import 'automation/values.dart';
import 'codec.dart';
import 'mcp/wire.dart';
import 'validation.dart';

const grantOwnerMethods = {
  'grants.list',
  'grants.get',
  'grants.configuration',
  'grants.create',
  'grants.replace',
  'grants.revoke',
};

Map<String, Object?> captureGrantOwnerResult(
  String method,
  Map<String, Object?> input,
) {
  final value = StrictCodec().decode(
    encodeMcpMessage(input, maxBytes: 512 * 1024),
    maxBytes: 512 * 1024,
  );
  if (!grantOwnerMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  switch (method) {
    case 'grants.list':
      requireFields(value, {'items'});
      final items = value['items'];
      if (items is! List || items.length > 32) _bad();
      final ids = <String>{};
      for (final raw in items) {
        final record = _public(_object(raw));
        if (!ids.add(record['id'] as String)) _bad();
      }
    case 'grants.get':
      requireFields(value, {'grant'});
      _public(_object(value['grant']));
    case 'grants.configuration':
      requireFields(value, {'command', 'args'});
      final command = value['command'], args = value['args'];
      if (command is! String ||
          args is! List ||
          args.length != 4 ||
          args[0] != '--app-root' ||
          args[2] != '--grant-id' ||
          args[1] is! String)
        _bad();
      requireUuid(args[3]);
      final root = args[1] as String;
      if (root.isEmpty ||
          root.length > 32767 ||
          root.contains(RegExp(r'[\x00-\x1f]')) ||
          !(RegExp(r'^[A-Za-z]:[\\/]').hasMatch(root) ||
              root.startsWith(r'\\')) ||
          command !=
              '$root${root.endsWith(r'\') || root.endsWith('/') ? '' : r'\'}mcp.exe')
        _bad();
    default:
      requireFields(value, {'grantId', 'revision'});
      requireUuid(value['grantId']);
      requireAutomationRevision(value['revision']);
  }
  return _freeze(value) as Map<String, Object?>;
}

Map<String, Object?> _public(Map<String, Object?> value) {
  requireFields(value, {
    'id',
    'workspaceId',
    'label',
    'revision',
    'scopes',
    'serverIds',
    'createdAt',
    'issuedAt',
    'expiresAt',
    'revokedAt',
  });
  requireUuid(value['id']);
  requireUuid(value['workspaceId']);
  automationText(value['label'], min: 1, max: 100);
  final revision = requireAutomationRevision(value['revision']);
  GrantScopePolicy.fromJson({
    'scopes': value['scopes'],
    'serverIds': value['serverIds'],
  });
  final created = automationTimestamp(value['createdAt']),
      issued = automationTimestamp(value['issuedAt']),
      expires = automationTimestamp(value['expiresAt']),
      revoked = nullableAutomationTimestamp(value['revokedAt']);
  final lifetime = expires.difference(issued);
  if (issued.isBefore(created) ||
      revision == 1 && issued != created ||
      revoked != null && revoked.isBefore(issued) ||
      lifetime < const Duration(minutes: 5) ||
      lifetime > const Duration(days: 30))
    _bad();
  return value;
}

Never _bad() => throw const FormatException('VALIDATION');
Map<String, Object?> _object(Object? value) =>
    value is Map<String, Object?> ? value : _bad();
Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable({
    for (final row in value.entries) row.key: _freeze(row.value),
  }),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};
