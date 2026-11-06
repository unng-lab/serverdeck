import 'dart:convert';
import 'dart:typed_data';

import '../console/console_models.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);
bool isCanonicalUuid(String value) =>
    value.length == 36 && _uuid.hasMatch(value);

enum FailureCode {
  invalidArgument('INVALID_ARGUMENT'),
  profileNotFound('PROFILE_NOT_FOUND'),
  conflict('CONFLICT'),
  authRequired('AUTH_REQUIRED'),
  accessRevoked('ACCESS_REVOKED'),
  grantExpired('GRANT_EXPIRED'),
  trustRequired('TRUST_REQUIRED'),
  hostKeyChanged('HOST_KEY_CHANGED'),
  authFailed('AUTH_FAILED'),
  passphraseRequired('PASSPHRASE_REQUIRED'),
  passphraseInvalid('PASSPHRASE_INVALID'),
  unsupportedKey('UNSUPPORTED_KEY'),
  unsupportedServer('UNSUPPORTED_SERVER'),
  networkError('NETWORK_ERROR'),
  timeout('TIMEOUT'),
  storageUnavailable('STORAGE_UNAVAILABLE'),
  protectionUnavailable('PROTECTION_UNAVAILABLE'),
  shuttingDown('SHUTTING_DOWN'),
  resourceExhausted('RESOURCE_EXHAUSTED'),
  cleanupRequired('CLEANUP_REQUIRED'),
  consoleNotFound('CONSOLE_NOT_FOUND'),
  consoleInactive('CONSOLE_INACTIVE'),
  consoleInputBusy('CONSOLE_INPUT_BUSY'),
  consoleReplayExpired('CONSOLE_REPLAY_EXPIRED');

  const FailureCode(this.wire);
  final String wire;
}

enum FailureReason { none, clockRollback, connectionCleanup, grantCleanup }

enum OperationField {
  profileId,
  displayName,
  host,
  port,
  username,
  authentication,
  passphrase,
  expectedRevision,
  mutationId,
  attemptId,
  sessionId,
  nonce,
  fingerprint,
  oldFingerprint,
  newFingerprint,
  acceptedFingerprint,
  limit,
  cursor,
  clientId,
  request,
}

final class OperationFailure implements Exception {
  const OperationFailure(
    this.code, {
    this.field,
    this.retryable = false,
    this.reason = FailureReason.none,
  });
  final FailureCode code;
  final OperationField? field;
  final bool retryable;
  final FailureReason reason;
  String get messageKey => switch (reason) {
    FailureReason.clockRollback => 'grant.clockRollbackRequiresRotation',
    FailureReason.connectionCleanup => 'connection.cleanupRequired',
    FailureReason.grantCleanup => 'grant.cleanupRequired',
    FailureReason.none => 'operation.${code.name}',
  };
  Map<String, Object> toJson() => {
    'code': code.wire,
    if (field != null) 'field': field!.name,
    'retryable': retryable,
    'messageKey': messageKey,
  };
  @override
  String toString() => code.wire;
}

/// Only these explicit projections may become operation results. No raw records/maps.
sealed class PublicValue {
  const PublicValue();
  Map<String, Object?> toJson();
}

final class OperationMeta {
  const OperationMeta({required this.dataRevision, required this.ownerEpoch});
  final int dataRevision;
  final String ownerEpoch;
  Map<String, Object> toJson() => {
    'dataRevision': dataRevision,
    'ownerEpoch': ownerEpoch,
  };
}

final class OperationResult<T extends PublicValue> {
  const OperationResult.success(T value, OperationMeta meta)
    : value = value,
      meta = meta,
      error = null;
  const OperationResult.failure(OperationFailure error)
    : error = error,
      value = null,
      meta = null;
  final T? value;
  final OperationMeta? meta;
  final OperationFailure? error;
  bool get ok => error == null;
  Map<String, Object?> toJson() => ok
      ? {'ok': true, 'value': value!.toJson(), 'meta': meta!.toJson()}
      : {'ok': false, 'error': error!.toJson()};
}

enum AuthKind { password, privateKey }

enum ConnectionState {
  disconnected,
  connecting,
  needTrust,
  needPassphrase,
  authenticating,
  connected,
  failed,
  cancelled,
}

enum TrustKind { first, replace, retain }

final class ProfileView extends PublicValue {
  const ProfileView({
    required this.profileId,
    required this.revision,
    required this.connectionRevision,
    required this.displayName,
    required this.host,
    required this.port,
    required this.username,
    required this.authKind,
    required this.hasCredential,
    required this.endpointId,
  });
  final String profileId, displayName, host, username, endpointId;
  final int revision, connectionRevision, port;
  final AuthKind authKind;
  final bool hasCredential;
  @override
  Map<String, Object?> toJson() => {
    'profileId': profileId,
    'revision': revision,
    'connectionRevision': connectionRevision,
    'displayName': displayName,
    'host': host,
    'port': port,
    'username': username,
    'authKind': authKind.name,
    'hasCredential': hasCredential,
    'endpointId': endpointId,
  };
}

final class ProfilesPage extends PublicValue {
  ProfilesPage({
    required List<ProfileView> items,
    required this.snapshotRevision,
    this.nextCursor,
  }) : items = List.unmodifiable(items);
  final List<ProfileView> items;
  final int snapshotRevision;
  final String? nextCursor;
  @override
  Map<String, Object?> toJson() => {
    'items': items.map((v) => v.toJson()).toList(),
    'snapshotRevision': snapshotRevision,
    if (nextCursor != null) 'nextCursor': nextCursor,
  };
}

final class TrustChallenge extends PublicValue {
  const TrustChallenge({
    required this.kind,
    required this.nonce,
    required this.attemptId,
    required this.endpointId,
    required this.profileRevision,
    required this.trustRevision,
    required this.observationRevision,
    required this.fingerprint,
    required this.expiresAt,
    required this.host,
    required this.port,
    required this.keyType,
    this.oldFingerprint,
  });
  final TrustKind kind;
  final String nonce, attemptId, endpointId, fingerprint, host, keyType;
  final String? oldFingerprint;
  final int profileRevision,
      trustRevision,
      observationRevision,
      expiresAt,
      port;
  @override
  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'nonce': nonce,
    'attemptId': attemptId,
    'endpointId': endpointId,
    'profileRevision': profileRevision,
    'trustRevision': trustRevision,
    'observationRevision': observationRevision,
    'fingerprint': fingerprint,
    'expiresAt': expiresAt,
    'host': host,
    'port': port,
    'keyType': keyType,
    if (oldFingerprint != null) 'oldFingerprint': oldFingerprint,
  };
}

final class PendingInput extends PublicValue {
  const PendingInput({
    required this.nonce,
    required this.attemptId,
    required this.expiresAt,
  });
  final String nonce, attemptId;
  final int expiresAt;
  @override
  Map<String, Object?> toJson() => {
    'nonce': nonce,
    'attemptId': attemptId,
    'expiresAt': expiresAt,
  };
}

final class ConnectionView extends PublicValue {
  const ConnectionView({
    required this.state,
    this.attemptId,
    this.sessionId,
    this.failureCode,
    this.challenge,
    this.pendingInput,
  });
  final ConnectionState state;
  final String? attemptId, sessionId;
  final FailureCode? failureCode;
  final TrustChallenge? challenge;
  final PendingInput? pendingInput;
  @override
  Map<String, Object?> toJson() => {
    'state': state.name,
    if (attemptId != null) 'attemptId': attemptId,
    if (sessionId != null) 'sessionId': sessionId,
    if (failureCode != null) 'failureCode': failureCode!.wire,
    if (challenge != null) 'challenge': challenge!.toJson(),
    if (pendingInput != null) 'pendingInput': pendingInput!.toJson(),
  };
}

final class TrustView extends PublicValue {
  const TrustView({
    required this.trustRevision,
    required this.observationRevision,
    required this.changed,
    this.acceptedFingerprint,
    this.keyType,
    this.observedFingerprint,
    this.observedKeyType,
    this.detectedAt,
    this.challenge,
  });
  final int trustRevision, observationRevision;
  final bool changed;
  final String? acceptedFingerprint,
      keyType,
      observedFingerprint,
      observedKeyType;
  final int? detectedAt;
  final TrustChallenge? challenge;
  @override
  Map<String, Object?> toJson() => {
    'trustRevision': trustRevision,
    'observationRevision': observationRevision,
    'changed': changed,
    if (acceptedFingerprint != null) 'acceptedFingerprint': acceptedFingerprint,
    if (keyType != null) 'keyType': keyType,
    if (observedFingerprint != null) 'observedFingerprint': observedFingerprint,
    if (observedKeyType != null) 'observedKeyType': observedKeyType,
    if (detectedAt != null) 'detectedAt': detectedAt,
    if (challenge != null) 'challenge': challenge!.toJson(),
  };
}

final class ProfileDetails extends PublicValue {
  const ProfileDetails({
    required this.profile,
    required this.connection,
    required this.trust,
  });
  final ProfileView profile;
  final ConnectionView connection;
  final TrustView trust;
  @override
  Map<String, Object?> toJson() => {
    'profile': profile.toJson(),
    'connection': connection.toJson(),
    'trust': trust.toJson(),
  };
}

final class MutationValue extends PublicValue {
  const MutationValue({
    required this.entityId,
    required this.revision,
    this.replayed = false,
  });
  final String entityId;
  final int revision;
  final bool replayed;
  @override
  Map<String, Object?> toJson() => {
    'entityId': entityId,
    'revision': revision,
    'replayed': replayed,
  };
}

/// Ephemeral inputs are intentionally outside PublicValue and have no JSON projection.
sealed class AuthenticationInput {
  AuthenticationInput();
  void dispose();
}

final class PasswordInput extends AuthenticationInput {
  PasswordInput(String password) : _password = password {
    _secretBound(password, empty: false);
  }
  String? _password;
  String get password => _password ?? (throw StateError('Credential cleared'));
  @override
  void dispose() => _password = null;
  @override
  String toString() => 'PasswordInput(redacted)';
}

final class PrivateKeyInput extends AuthenticationInput {
  PrivateKeyInput(Uint8List bytes, {String? passphrase})
    : _passphrase = passphrase {
    if (bytes.isEmpty || bytes.length > 1024 * 1024) {
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.authentication,
      );
    }
    if (passphrase != null) _secretBound(passphrase);
    _bytes = Uint8List.fromList(bytes);
  }
  late final Uint8List _bytes;
  String? _passphrase;
  bool _disposed = false;
  Uint8List get bytes {
    if (_disposed) throw StateError('Credential cleared');
    return _bytes.asUnmodifiableView();
  }

  String? get passphrase {
    if (_disposed) throw StateError('Credential cleared');
    return _passphrase;
  }

  @override
  void dispose() {
    _bytes.fillRange(0, _bytes.length, 0);
    _passphrase = null;
    _disposed = true;
  }

  @override
  String toString() => 'PrivateKeyInput(redacted)';
}

void _secretBound(String value, {bool empty = true}) {
  if (!isWellFormedUnicode(value) ||
      (!empty && value.isEmpty) ||
      value.length > 65536 ||
      utf8.encode(value).length > 65536) {
    throw const OperationFailure(
      FailureCode.invalidArgument,
      field: OperationField.authentication,
    );
  }
}

final class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.host,
    this.port,
    required this.username,
    required this.authentication,
  });
  final String displayName, host, username;
  // Preserve absence for exact idempotency payload; validation defaults to22.
  final int? port;
  final AuthenticationInput authentication;
}

final class ProfilePatch {
  const ProfilePatch({
    this.displayName,
    this.host,
    this.port,
    this.username,
    this.authentication,
  });
  final String? displayName, host, username;
  final int? port;
  final AuthenticationInput? authentication;
  bool get isEmpty =>
      displayName == null &&
      host == null &&
      port == null &&
      username == null &&
      authentication == null;
}

class TrustDecision {
  const TrustDecision({
    required this.profileId,
    required this.attemptId,
    required this.nonce,
    required this.expectedProfileRevision,
    required this.expectedTrustRevision,
    required this.expectedObservationRevision,
    required this.fingerprint,
    required this.mutationId,
    required this.confirmed,
  });
  final String profileId, attemptId, nonce, fingerprint, mutationId;
  final int expectedProfileRevision,
      expectedTrustRevision,
      expectedObservationRevision;
  final bool confirmed;
}

final class ReplacementDecision extends TrustDecision {
  const ReplacementDecision({
    required super.profileId,
    required super.attemptId,
    required super.nonce,
    required super.expectedProfileRevision,
    required super.expectedTrustRevision,
    required super.expectedObservationRevision,
    required super.fingerprint,
    required super.mutationId,
    required super.confirmed,
    required this.oldFingerprint,
    required this.newFingerprint,
  });
  final String oldFingerprint, newFingerprint;
}

final class RetentionDecision extends TrustDecision {
  const RetentionDecision({
    required super.profileId,
    required super.attemptId,
    required super.nonce,
    required super.expectedProfileRevision,
    required super.expectedTrustRevision,
    required super.expectedObservationRevision,
    required super.fingerprint,
    required super.mutationId,
    required super.confirmed,
    required this.acceptedFingerprint,
  });
  final String acceptedFingerprint;
}

/// Use before mutating a canonical revision; never persist an unrepresentable result.
int nextRevision(int current) {
  if (current < 1 || current > 9007199254740991) {
    throw const OperationFailure(FailureCode.storageUnavailable);
  }
  if (current == 9007199254740991) {
    throw const OperationFailure(FailureCode.resourceExhausted);
  }
  return current + 1;
}

bool isWellFormedUnicode(String value) =>
    !value.runes.any((rune) => rune >= 0xd800 && rune <= 0xdfff);

/// Explicit console projections; credential records and arbitrary payload maps are excluded.
final class ConsoleValue extends PublicValue {
  const ConsoleValue(this.console);
  final ConsoleProjection console;
  @override
  Map<String, Object?> toJson() => console.toJson();
}
