import 'dart:convert';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');
Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : _blocked();
String _text(Object? value) => value is String ? value : _blocked();
void _timestamp(Object? value) {
  final text = _text(value);
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$')
          .hasMatch(text) ||
      DateTime.tryParse(text)?.toIso8601String() != text)
    _blocked();
}

void _times(Map<String, Object?> value) {
  _timestamp(value['createdAt']);
  _timestamp(value['updatedAt']);
  if (_text(value['createdAt']).compareTo(_text(value['updatedAt'])) > 0)
    _blocked();
}

void _base64(Object? value, {int? exactBytes, int? maxBytes}) {
  final text = _text(value);
  if (maxBytes != null && text.length > ((maxBytes + 2) ~/ 3) * 4) _blocked();
  try {
    final bytes = base64.decode(text);
    if (bytes.isEmpty ||
        base64.encode(bytes) != text ||
        (exactBytes != null && bytes.length != exactBytes) ||
        (maxBytes != null && bytes.length > maxBytes))
      _blocked();
  } on FormatException {
    _blocked();
  }
}

String nextRevision(String revision) {
  requireRevision(revision, allowZero: true);
  final next = BigInt.parse(revision) + BigInt.one;
  if (next > maxRevision) throw StateError('RESOURCE_LIMIT');
  return next.toString();
}

class ProfileRecord {
  ProfileRecord._(this._value);
  factory ProfileRecord.fromJson(Map<String, Object?> value) =>
      ProfileRecord._parse(value, trusted: false);
  factory ProfileRecord.fromTrustedJson(Map<String, Object?> value) =>
      ProfileRecord._parse(value, trusted: true);
  factory ProfileRecord._parse(
    Map<String, Object?> value, {
    required bool trusted,
  }) {
    requireFields(value, {
      'id',
      'revision',
      'name',
      'address',
      'port',
      'sshUser',
      'tags',
      'credentialRef',
      'credentialRevision',
      'connectionRevision',
      'trustRevision',
      'createdAt',
      'updatedAt',
    });
    requireUuid(value['id']);
    for (final field in [
      'revision',
      'credentialRevision',
      'connectionRevision',
      'trustRevision',
    ]) {
      requireRevision(value[field]);
    }
    if (value['credentialRef'] != null) requireUuid(value['credentialRef']);
    final normalized = normalizeProfileFields(value);
    for (final field in ['name', 'address', 'port', 'sshUser']) {
      if (value[field] != normalized[field]) _blocked();
    }
    final tags = value['tags'] as List;
    final normalTags = normalized['tags'] as List;
    for (var i = 0; i < tags.length; i++) {
      if (tags[i] != normalTags[i]) _blocked();
    }
    _times(value);
    if (utf8.encode(jsonEncode(value)).length > 16 * 1024) _blocked();
    final revision = BigInt.parse(value['revision'] as String);
    for (final field in [
      'credentialRevision',
      'connectionRevision',
      'trustRevision',
    ]) {
      if (BigInt.parse(value[field] as String) > revision) _blocked();
    }
    if (trusted
        ? BigInt.parse(value['connectionRevision'] as String) >
              BigInt.parse(value['trustRevision'] as String)
        : value['connectionRevision'] != value['trustRevision'])
      _blocked();
    return ProfileRecord._(
      Map.unmodifiable({
        ...value,
        'tags': List<String>.unmodifiable(tags.cast<String>()),
      }),
    );
  }
  final Map<String, Object?> _value;
  String get id => _value['id'] as String;
  String get revision => _value['revision'] as String;
  String? get credentialRef => _value['credentialRef'] as String?;
  String get credentialRevision => _value['credentialRevision'] as String;
  String get connectionRevision => _value['connectionRevision'] as String;
  String get trustRevision => _value['trustRevision'] as String;
  String get updatedAt => _value['updatedAt'] as String;
  String get name => _value['name'] as String;
  Map<String, Object?> toJson() => {
    ..._value,
    'tags': List<String>.of(_value['tags'] as List<String>),
  };
  ProfileView view(CredentialRecord? credential) {
    if ((credentialRef == null) != (credential == null) ||
        (credential != null &&
            (credential.id != credentialRef ||
                credential.profileId != id ||
                credential.revision != credentialRevision)))
      _blocked();
    return ProfileView(
      id: id,
      revision: revision,
      name: name,
      address: _value['address'] as String,
      port: _value['port'] as int,
      sshUser: _value['sshUser'] as String,
      tags: _value['tags'] as List<String>,
      credentialRevision: credentialRevision,
      connectionRevision: _value['connectionRevision'] as String,
      trustRevision: _value['trustRevision'] as String,
      createdAt: _value['createdAt'] as String,
      updatedAt: _value['updatedAt'] as String,
      credentialKind: credential?.kind ?? CredentialKind.none,
      credentialConfigured: credential != null,
    );
  }
}

class CredentialRecord {
  CredentialRecord._(this._value, this.kind);
  factory CredentialRecord.fromJson(Map<String, Object?> value) {
    requireFields(value, {
      'id',
      'revision',
      'profileId',
      'kind',
      'protectedBlob',
      'createdAt',
      'updatedAt',
    });
    requireUuid(value['id']);
    requireUuid(value['profileId']);
    requireRevision(value['revision']);
    final kind = switch (value['kind']) {
      'password' => CredentialKind.password,
      'privateKey' => CredentialKind.privateKey,
      _ => _blocked(),
    };
    StrictCodec().encode(value, maxBytes: 512 * 1024);
    _base64(value['protectedBlob'], maxBytes: 256 * 1024);
    _times(value);
    // Replace creates an immutable record; keep does not change its timestamps.
    if (value['createdAt'] != value['updatedAt']) _blocked();
    return CredentialRecord._(Map.unmodifiable(value), kind);
  }
  final Map<String, Object?> _value;
  final CredentialKind kind;
  String get id => _value['id'] as String;
  String get profileId => _value['profileId'] as String;
  String get revision => _value['revision'] as String;
  String get protectedBlob => _value['protectedBlob'] as String;
  Map<String, Object?> toJson() => Map.of(_value);
}

class MutationReceipt {
  MutationReceipt._(this._value, this.result);
  factory MutationReceipt.fromJson(Map<String, Object?> value) =>
      MutationReceipt._parse(value, trusted: false);
  factory MutationReceipt.fromTrustedJson(Map<String, Object?> value) =>
      MutationReceipt._parse(value, trusted: true);
  factory MutationReceipt._parse(
    Map<String, Object?> value, {
    required bool trusted,
  }) {
    StrictCodec().encode(value, maxBytes: 4096);
    requireFields(value, {
      'requestId',
      'inputDigest',
      'operation',
      'profileId',
      'result',
      'committedAt',
    });
    requireUuid(value['requestId']);
    _base64(value['inputDigest'], exactBytes: 32);
    final operation = _text(value['operation']);
    final trustMutation =
        trusted &&
        (operation == 'servers.trust.confirm' ||
            operation == 'servers.trust.revoke');
    if (!trustMutation &&
        !ApiMethod.values
            .where((m) => m.isMutation)
            .any((m) => m.wireName == operation))
      _blocked();
    final body = _map(value['result']);
    validateMethodResult(trustMutation ? 'profiles.update' : operation, body);
    final entityRevision = BigInt.parse(body['entityRevision'] as String);
    final committedRevision = BigInt.parse(body['storeRevision'] as String);
    if ((operation == 'profiles.create' && entityRevision != BigInt.one) ||
        ((trustMutation ||
                operation == 'profiles.update' ||
                operation == 'settings.update') &&
            entityRevision <= BigInt.one) ||
        (operation == 'profiles.delete' &&
            entityRevision >= committedRevision) ||
        entityRevision >
            committedRevision +
                (operation == 'settings.update' ? BigInt.one : BigInt.zero))
      _blocked();
    if (value['profileId'] != body['entityId']) _blocked();
    if (value['profileId'] != null) requireUuid(value['profileId']);
    _timestamp(value['committedAt']);
    final result = MutationResult(
      entityId: body['entityId'] as String?,
      entityRevision: body['entityRevision'] as String?,
      storeRevision: body['storeRevision'] as String,
      deleted: body['deleted'] as bool,
    );
    return MutationReceipt._(
      Map.unmodifiable({
        ...value,
        'result': Map<String, Object?>.unmodifiable(body),
      }),
      result,
    );
  }
  final Map<String, Object?> _value;
  final MutationResult result;
  String get requestId => _value['requestId'] as String;
  String get inputDigest => _value['inputDigest'] as String;
  String get operation => _value['operation'] as String;
  String get committedAt => _value['committedAt'] as String;
  Map<String, Object?> toJson() => {..._value, 'result': result.toJson()};
  MutationReceiptView get view => MutationReceiptView(
    requestId: requestId,
    operation: operation,
    profileId: _value['profileId'] as String?,
    result: result,
    committedAt: committedAt,
  );
}

class WorkspaceState {
  WorkspaceState._({
    required this.schemaVersion,
    required this.workspaceId,
    required this.receiptKeyId,
    required this.ownerSid,
    required this.storeRevision,
    required this.profiles,
    required this.credentials,
    required this.settings,
    required this.receipts,
  });
  factory WorkspaceState.empty({
    required String workspaceId,
    required String receiptKeyId,
    required String ownerSid,
  }) => WorkspaceState.fromJson(
    {
      'schemaVersion': 1,
      'workspaceId': workspaceId,
      'receiptKeyId': receiptKeyId,
      'ownerSid': ownerSid,
      'storeRevision': '0',
      'profiles': <String, Object?>{},
      'credentials': <String, Object?>{},
      'settings': const SettingsView().toJson(),
      'receipts': <String, Object?>{},
    },
    workspaceId: workspaceId,
    receiptKeyId: receiptKeyId,
    ownerSid: ownerSid,
  );

  factory WorkspaceState.fromJson(
    Map<String, Object?> value, {
    required String workspaceId,
    required String receiptKeyId,
    required String ownerSid,
  }) => WorkspaceState._parse(
    value,
    workspaceId: workspaceId,
    receiptKeyId: receiptKeyId,
    ownerSid: ownerSid,
    trusted: false,
  );

  /// Explicit schema3 foundation view; not proof of the full retained graph.
  factory WorkspaceState.fromTrustedJson(
    Map<String, Object?> value, {
    required String workspaceId,
    required String receiptKeyId,
    required String ownerSid,
  }) => WorkspaceState._parse(
    value,
    workspaceId: workspaceId,
    receiptKeyId: receiptKeyId,
    ownerSid: ownerSid,
    trusted: true,
  );

  factory WorkspaceState._parse(
    Map<String, Object?> value, {
    required String workspaceId,
    required String receiptKeyId,
    required String ownerSid,
    required bool trusted,
  }) {
    final schema = trusted ? 3 : 1;
    if (value['schemaVersion'] is! int || value['schemaVersion'] != schema)
      throw StateError('INCOMPATIBLE');
    try {
      requireFields(value, {
        'schemaVersion',
        'workspaceId',
        'receiptKeyId',
        'ownerSid',
        'storeRevision',
        'profiles',
        'credentials',
        'settings',
        'receipts',
      });
      requireUuid(workspaceId);
      requireUuid(receiptKeyId);
      if (!RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(ownerSid) ||
          value['workspaceId'] != workspaceId ||
          value['receiptKeyId'] != receiptKeyId ||
          value['ownerSid'] != ownerSid)
        _blocked();
      final revision = requireRevision(value['storeRevision'], allowZero: true);
      final rawProfiles = _map(value['profiles']),
          rawCredentials = _map(value['credentials']),
          rawReceipts = _map(value['receipts']);
      if (rawProfiles.length > 250 ||
          rawCredentials.length > rawProfiles.length ||
          rawReceipts.length > 10000)
        _blocked();
      final profiles = <String, ProfileRecord>{};
      for (final entry in rawProfiles.entries) {
        final profile = trusted
            ? ProfileRecord.fromTrustedJson(_map(entry.value))
            : ProfileRecord.fromJson(_map(entry.value));
        if (entry.key != profile.id ||
            BigInt.parse(profile.revision) > BigInt.parse(revision))
          _blocked();
        profiles[entry.key] = profile;
      }
      final credentials = <String, CredentialRecord>{};
      for (final entry in rawCredentials.entries) {
        final credential = CredentialRecord.fromJson(_map(entry.value));
        if (entry.key != credential.id) _blocked();
        credentials[entry.key] = credential;
      }
      final usedCredentials = <String>{};
      for (final profile in profiles.values) {
        final ref = profile.credentialRef;
        if (ref == null) continue;
        final credential = credentials[ref];
        if (credential == null ||
            credential.profileId != profile.id ||
            credential.revision != profile.credentialRevision ||
            !usedCredentials.add(ref))
          _blocked();
      }
      if (usedCredentials.length != credentials.length) _blocked();
      final settingsJson = _map(value['settings']);
      StrictCodec().encode(settingsJson, maxBytes: 4096);
      validateMethodResult('settings.get', {
        'storeRevision': revision,
        'settings': settingsJson,
      });
      final settings = SettingsView(
        revision: settingsJson['revision'] as String,
        theme: ThemePreference.values.singleWhere(
          (t) => t.name == settingsJson['theme'],
        ),
        reduceMotion: settingsJson['reduceMotion'] as bool,
        selectedProfileId: settingsJson['selectedProfileId'] as String?,
      );
      if ((settings.selectedProfileId != null &&
              !profiles.containsKey(settings.selectedProfileId)) ||
          BigInt.parse(settings.revision) > BigInt.parse(revision) + BigInt.one)
        _blocked();
      final receipts = <String, MutationReceipt>{};
      final committedRevisions = <String>{};
      for (final entry in rawReceipts.entries) {
        final receipt = trusted
            ? MutationReceipt.fromTrustedJson(_map(entry.value))
            : MutationReceipt.fromJson(_map(entry.value));
        final committedRevision = receipt.result.storeRevision;
        if (entry.key != receipt.requestId ||
            BigInt.parse(committedRevision) < BigInt.one ||
            BigInt.parse(committedRevision) > BigInt.parse(revision) ||
            !committedRevisions.add(committedRevision))
          _blocked();
        receipts[entry.key] = receipt;
      }
      // Each successful mutation increments once and keeps exactly one receipt.
      if (BigInt.from(receipts.length) != BigInt.parse(revision)) _blocked();
      return WorkspaceState._(
        schemaVersion: schema,
        workspaceId: workspaceId,
        receiptKeyId: receiptKeyId,
        ownerSid: ownerSid,
        storeRevision: revision,
        profiles: Map.unmodifiable(profiles),
        credentials: Map.unmodifiable(credentials),
        settings: settings,
        receipts: Map.unmodifiable(receipts),
      );
    } on FormatException {
      _blocked();
    }
  }
  final int schemaVersion;
  final String workspaceId, receiptKeyId, ownerSid, storeRevision;
  final Map<String, ProfileRecord> profiles;
  final Map<String, CredentialRecord> credentials;
  final SettingsView settings;
  final Map<String, MutationReceipt> receipts;
  bool get isInitialEmpty =>
      storeRevision == '0' &&
      profiles.isEmpty &&
      credentials.isEmpty &&
      receipts.isEmpty &&
      settings.revision == '1' &&
      settings.theme == ThemePreference.system &&
      !settings.reduceMotion &&
      settings.selectedProfileId == null;
  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'workspaceId': workspaceId,
    'receiptKeyId': receiptKeyId,
    'ownerSid': ownerSid,
    'storeRevision': storeRevision,
    'profiles': {for (final p in profiles.entries) p.key: p.value.toJson()},
    'credentials': {
      for (final c in credentials.entries) c.key: c.value.toJson(),
    },
    'settings': settings.toJson(),
    'receipts': {for (final r in receipts.entries) r.key: r.value.toJson()},
  };
}
