import 'codec.dart';
import 'connections.dart';
import 'validation.dart';

/// Public immutable owner confirmation metadata. Structural validity is not
/// current native authority, source qualification or permission to execute.
final class ExecutorEnrollment {
  factory ExecutorEnrollment.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 8192);
    requireFields(value, {
      'format',
      'workspaceId',
      'serverId',
      'connection',
      'hostId',
      'runtimeVersion',
      'lockDigest',
      'registryDigest',
      'compilerDigest',
      'bridgeDigest',
      'createdAt',
    });
    if (value['format'] is! int || value['format'] != 1) _bad();
    final workspace = requireUuid(value['workspaceId']);
    final server = requireUuid(value['serverId']);
    requireUuid(value['hostId']);
    final raw = value['connection'];
    if (raw is! Map<String, Object?>) _bad();
    final connection = ConnectionIdentity.fromJson(raw);
    if (connection.profileId != server) _bad();
    final version = value['runtimeVersion'];
    if (version is! String ||
        !RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+\+[a-f0-9]{64}$').hasMatch(version) ||
        version.length > 100)
      _bad();
    for (final field in [
      'lockDigest',
      'registryDigest',
      'compilerDigest',
      'bridgeDigest',
    ]) {
      if (value[field] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(value[field] as String))
        _bad();
    }
    final created = value['createdAt'];
    if (created is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
            .hasMatch(created) ||
        DateTime.tryParse(created)?.toIso8601String() != created)
      _bad();
    return ExecutorEnrollment._(
      Map.unmodifiable({...value, 'connection': connection.toJson()}),
      workspace,
      server,
      connection,
    );
  }
  const ExecutorEnrollment._(
    this._value,
    this.workspaceId,
    this.serverId,
    this.connection,
  );
  final Map<String, Object?> _value;
  final String workspaceId, serverId;
  final ConnectionIdentity connection;
  String get hostId => _value['hostId'] as String;
  String get runtimeVersion => _value['runtimeVersion'] as String;
  String get lockDigest => _value['lockDigest'] as String;
  String get registryDigest => _value['registryDigest'] as String;
  String get compilerDigest => _value['compilerDigest'] as String;
  String get bridgeDigest => _value['bridgeDigest'] as String;
  Map<String, Object?> toJson() => _value;
}

Never _bad() => throw const FormatException('VALIDATION');
