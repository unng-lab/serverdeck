import 'models.dart';
import 'profile_validation.dart';
import 'validation.dart';

Never _invalid() => throw const FormatException('VALIDATION');
Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : _invalid();
void _exact(Object? actual, Object expected) {
  if (actual.runtimeType != expected.runtimeType || actual != expected)
    _invalid();
}

void _capabilities(Object? value) {
  if (value is! List) _invalid();
  final allowed = Capability.values.map((c) => c.wireName).toSet();
  String? previous;
  for (final item in value) {
    if (item is! String ||
        !allowed.contains(item) ||
        (previous != null && previous.compareTo(item) >= 0))
      _invalid();
    previous = item;
  }
}

void _identity(Map<String, Object?> value) {
  _exact(value['product'], 'serverdeck-next');
  _exact(value['apiMajor'], 1);
  _exact(value['apiMinor'], 0);
  _exact(value['workspaceSlot'], 'default');
  requireUuid(value['generation']);
}

void validateHello(Map<String, Object?> value) {
  requireFields(value, {'hello'});
  final body = _map(value['hello']);
  requireFields(body, {
    'product',
    'apiMajor',
    'apiMinor',
    'workspaceSlot',
    'generation',
    'serverNonce',
  });
  _identity(body);
  requireNonce(body['serverNonce']);
}

void validateAuthenticate(Map<String, Object?> value) {
  requireFields(value, {'authenticate'});
  final body = _map(value['authenticate']);
  requireFields(body, {
    'clientNonce',
    'clientBuildId',
    'requestedCapabilities',
    'proof',
  });
  requireNonce(body['clientNonce']);
  requireNonce(body['proof']);
  if (body['clientBuildId'] is! String ||
      (body['clientBuildId'] as String).isEmpty)
    _invalid();
  _capabilities(body['requestedCapabilities']);
}

void validateAuthenticated(Map<String, Object?> value) {
  requireFields(value, {'authenticated'});
  final body = _map(value['authenticated']);
  requireFields(body, {
    'sessionId',
    'capabilities',
    'idleLeaseSeconds',
    'proof',
  });
  requireNonce(body['sessionId']);
  requireNonce(body['proof']);
  _capabilities(body['capabilities']);
  _exact(body['idleLeaseSeconds'], 60);
}

void _timestamp(Object? value) {
  if (value is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$').hasMatch(value))
    _invalid();
  final parsed = DateTime.tryParse(value);
  if (parsed == null || parsed.toIso8601String() != value) _invalid();
}

void _profile(Object? value) {
  final body = _map(value);
  requireFields(body, {
    'id',
    'revision',
    'name',
    'address',
    'port',
    'sshUser',
    'tags',
    'credentialRevision',
    'connectionRevision',
    'trustRevision',
    'createdAt',
    'updatedAt',
    'credential',
  });
  requireUuid(body['id']);
  for (final field in [
    'revision',
    'credentialRevision',
    'connectionRevision',
    'trustRevision',
  ]) {
    requireRevision(body[field]);
  }
  final normalized = normalizeProfileFields(body);
  for (final field in ['name', 'address', 'sshUser', 'port']) {
    if (body[field] != normalized[field]) _invalid();
  }
  final tags = body['tags'] as List;
  final normalizedTags = normalized['tags'] as List;
  for (var i = 0; i < tags.length; i++) {
    if (tags[i] != normalizedTags[i]) _invalid();
  }
  _timestamp(body['createdAt']);
  _timestamp(body['updatedAt']);
  if ((body['createdAt'] as String).compareTo(body['updatedAt'] as String) > 0)
    _invalid();
  final credential = _map(body['credential']);
  requireFields(credential, {'kind', 'configured'});
  if (!CredentialKind.values.map((c) => c.name).contains(credential['kind']) ||
      credential['configured'] is! bool ||
      credential['configured'] != (credential['kind'] != 'none'))
    _invalid();
}

void _settings(Object? value) {
  final body = _map(value);
  requireFields(body, {
    'revision',
    'theme',
    'reduceMotion',
    'selectedProfileId',
  });
  requireRevision(body['revision']);
  if (!ThemePreference.values.map((t) => t.name).contains(body['theme']) ||
      body['reduceMotion'] is! bool)
    _invalid();
  if (body['selectedProfileId'] != null) requireUuid(body['selectedProfileId']);
}

void _mutation(Object? value, {String? operation}) {
  final body = _map(value);
  requireFields(body, {
    'entityId',
    'entityRevision',
    'storeRevision',
    'deleted',
  });
  if (body['entityId'] != null) requireUuid(body['entityId']);
  if (body['entityRevision'] != null) requireRevision(body['entityRevision']);
  requireRevision(body['storeRevision'], allowZero: true);
  if (body['deleted'] is! bool) _invalid();
  if (operation != null) {
    if (operation == 'settings.update') {
      if (body['entityId'] != null) _invalid();
    } else {
      requireUuid(body['entityId']);
    }
    requireRevision(body['entityRevision']);
    _exact(body['deleted'], operation == 'profiles.delete');
  }
}

void validateMethodResult(String method, Map<String, Object?> value) {
  switch (method) {
    case 'readiness.get':
      requireFields(value, {
        'state',
        'reason',
        'product',
        'apiMajor',
        'apiMinor',
        'workspaceSlot',
        'workspaceId',
        'generation',
        'storageSchema',
        'features',
        'clientPlatform',
      });
      _identity(value);
      _exact(value['storageSchema'], 1);
      _exact(value['clientPlatform'], 'windows-x64');
      if (!{
        'starting',
        'recovering',
        'ready',
        'storage-blocked',
        'incompatible',
        'stopping',
        'unavailable',
      }.contains(value['state']))
        _invalid();
      if (value['reason'] != null &&
          !ErrorCode.values.map((e) => e.wireName).contains(value['reason']))
        _invalid();
      if (value['workspaceId'] != null) requireUuid(value['workspaceId']);
      if (value['state'] == 'ready' && value['workspaceId'] == null) _invalid();
      final features = _map(value['features']);
      requireFields(features, {'profiles', 'ssh', 'jobs', 'backend'});
      _exact(features['profiles'], true);
      for (final feature in ['ssh', 'jobs', 'backend']) {
        _exact(features[feature], false);
      }
    case 'session.ping':
      requireFields(value, {'leaseSeconds'});
      _exact(value['leaseSeconds'], 60);
    case 'session.close':
      requireFields(value, {'closed'});
      _exact(value['closed'], true);
    case 'profiles.list':
      requireFields(value, {'storeRevision', 'profiles'});
      requireRevision(value['storeRevision'], allowZero: true);
      final profiles = value['profiles'];
      if (profiles is! List || profiles.length > 250) _invalid();
      final ids = <Object?>{};
      for (final profile in profiles) {
        _profile(profile);
        if (!ids.add(_map(profile)['id'])) _invalid();
      }
    case 'profiles.get':
      requireFields(value, {'storeRevision', 'profile'});
      requireRevision(value['storeRevision'], allowZero: true);
      _profile(value['profile']);
    case 'profiles.create':
    case 'profiles.update':
    case 'profiles.delete':
    case 'settings.update':
      _mutation(value, operation: method);
    case 'settings.get':
      requireFields(value, {'storeRevision', 'settings'});
      requireRevision(value['storeRevision'], allowZero: true);
      _settings(value['settings']);
    case 'mutations.get':
      requireFields(value, {'state', 'result'});
      if (!{
        'queued',
        'running',
        'committed',
        'not-found',
      }.contains(value['state']))
        _invalid();
      if (value['state'] == 'committed') {
        _mutation(value['result']);
      } else if (value['result'] != null) {
        _invalid();
      }
    case 'mutations.recent':
      requireFields(value, {'receipts', 'truncated'});
      final receipts = value['receipts'];
      if (receipts is! List ||
          receipts.length > 100 ||
          value['truncated'] is! bool)
        _invalid();
      final ids = <String>{};
      String? previous;
      for (final receipt in receipts) {
        final body = _map(receipt);
        requireFields(body, {
          'requestId',
          'operation',
          'profileId',
          'result',
          'committedAt',
        });
        if (!ids.add(requireUuid(body['requestId']))) _invalid();
        final operation = body['operation'];
        if (operation is! String ||
            !ApiMethod.values
                .where((m) => m.isMutation)
                .map((m) => m.wireName)
                .contains(operation))
          _invalid();
        if (operation == 'settings.update') {
          if (body['profileId'] != null) _invalid();
        } else {
          requireUuid(body['profileId']);
        }
        _mutation(body['result'], operation: operation);
        if (_map(body['result'])['entityId'] != body['profileId']) _invalid();
        _timestamp(body['committedAt']);
        final timestamp = body['committedAt'] as String;
        if (previous != null && previous.compareTo(timestamp) < 0) _invalid();
        previous = timestamp;
      }
    default:
      throw const FormatException('UNSUPPORTED');
  }
}
