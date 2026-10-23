import 'codec.dart';
import 'host_trust.dart'
    show SshHostPin, SshTransportFailure, TrustedLocalError;
import 'validation.dart';

const connectionOwnerMethods = {
  'servers.connect',
  'servers.connectStatus',
  'servers.connectCancel',
  'servers.connection',
  'servers.disconnect',
};

Never _invalid() => throw const FormatException('VALIDATION');
Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) _invalid();
  return value;
}

/// Captured public identity; structural validity never establishes live trust.
final class ConnectionIdentity {
  factory ConnectionIdentity.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 4096);
    requireFields(value, {
      'profileId',
      'connectionRevision',
      'credentialRevision',
      'trustRevision',
      'key',
    });
    final profile = requireUuid(value['profileId']);
    final connection = requireRevision(value['connectionRevision']);
    final credential = requireRevision(value['credentialRevision']);
    final trust = requireRevision(value['trustRevision']);
    if (BigInt.parse(connection) > BigInt.parse(trust)) _invalid();
    SshHostPin key;
    try {
      key = SshHostPin.fromJson(_map(value['key']));
    } on SshTransportFailure {
      _invalid();
    }
    return ConnectionIdentity._(profile, connection, credential, trust, key);
  }
  const ConnectionIdentity._(
    this.profileId,
    this.connectionRevision,
    this.credentialRevision,
    this.trustRevision,
    this.key,
  );
  final String profileId, connectionRevision, credentialRevision, trustRevision;
  final SshHostPin key;
  Map<String, Object?> toJson() => Map.unmodifiable({
    'profileId': profileId,
    'connectionRevision': connectionRevision,
    'credentialRevision': credentialRevision,
    'trustRevision': trustRevision,
    'key': Map<String, Object?>.unmodifiable(key.toJson()),
  });
}

/// One immutable session view of the shared transport, never a lease/capability.
final class ConnectionSnapshot {
  factory ConnectionSnapshot.fromJson(Map<String, Object?> value) {
    StrictCodec().encode(value, maxBytes: 8192);
    requireFields(value, {'profileId', 'state', 'interested', 'identity'});
    final profile = requireUuid(value['profileId']);
    final state = value['state'];
    final interested = value['interested'];
    if (state is! String ||
        !const {
          'disconnected',
          'connecting',
          'connected',
          'closing',
        }.contains(state) ||
        interested is! bool)
      _invalid();
    final identity = value['identity'] == null
        ? null
        : ConnectionIdentity.fromJson(_map(value['identity']));
    if ((state == 'disconnected') != (identity == null) ||
        identity != null && identity.profileId != profile ||
        (state == 'disconnected' || state == 'closing') && interested)
      _invalid();
    return ConnectionSnapshot._(profile, state, interested, identity);
  }
  const ConnectionSnapshot._(
    this.profileId,
    this.state,
    this.interested,
    this.identity,
  );
  final String profileId, state;
  final bool interested;
  final ConnectionIdentity? identity;
  Map<String, Object?> toJson() => Map.unmodifiable({
    'profileId': profileId,
    'state': state,
    'interested': interested,
    'identity': identity?.toJson(),
  });
}

/// Owner adapter must authorize the exact method before parsing private input.
Map<String, Object?> captureConnectionParams(
  String method,
  Map<String, Object?> value,
) {
  if (!connectionOwnerMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  StrictCodec().encode(value, maxBytes: 4096);
  final field =
      method == 'servers.connectStatus' || method == 'servers.connectCancel'
      ? 'operationId'
      : 'profileId';
  requireFields(value, {field});
  requireUuid(value[field]);
  return Map.unmodifiable(value);
}

/// Only verified format3 composition selects this boundary. No route admission.
Map<String, Object?> captureConnectionResult(
  String method,
  Map<String, Object?> value,
) {
  if (!connectionOwnerMethods.contains(method))
    throw const FormatException('UNSUPPORTED');
  StrictCodec().encode(value, maxBytes: 8192);
  if (method == 'servers.connection' || method == 'servers.disconnect')
    return ConnectionSnapshot.fromJson(value).toJson();
  requireUuid(value['operationId']);
  if (method == 'servers.connectCancel') {
    requireFields(value, {'operationId', 'cancelled'});
    if (value['cancelled'] is! bool) _invalid();
    return Map.unmodifiable(value);
  }
  switch (value['state']) {
    case 'running':
      requireFields(value, {'operationId', 'state'});
    case 'succeeded' when method == 'servers.connectStatus':
      requireFields(value, {'operationId', 'state', 'connection'});
      final connection = ConnectionSnapshot.fromJson(_map(value['connection']));
      if (connection.state != 'connected' || !connection.interested) _invalid();
      return Map.unmodifiable({...value, 'connection': connection.toJson()});
    case 'failed' when method == 'servers.connectStatus':
      requireFields(value, {'operationId', 'state', 'code'});
      if (value['code'] is! String ||
          !TrustedLocalError.codes.contains(value['code']))
        _invalid();
    default:
      _invalid();
  }
  return Map.unmodifiable(value);
}
