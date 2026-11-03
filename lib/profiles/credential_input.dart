import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import '../domain/models.dart';
import 'credential_parser.dart';
import 'key_parse_worker.dart';

abstract interface class SecretProtector {
  Future<Uint8List> protect(Uint8List bytes, String purpose);
}

/// Owned encrypted material, copied into a record before disposal. No projection.
final class PreparedCredential {
  PreparedCredential._(this.kind, this._ciphertext, this.inspection);
  final AuthKind kind;
  final Uint8List _ciphertext;
  final KeyInspection? inspection;
  bool _disposed = false;
  Uint8List get ciphertext {
    if (_disposed) throw StateError('Credential cleared');
    return _ciphertext.asUnmodifiableView();
  }

  void dispose() {
    _ciphertext.fillRange(0, _ciphertext.length, 0);
    _disposed = true;
  }

  @override
  String toString() => 'PreparedCredential(redacted)';
}

/// Preparation is outside a database transaction. Callers recheck their fence
/// and authorization at commit, then dispose both input and prepared material.
final class CredentialPreparer {
  const CredentialPreparer(this.protector, this.inspector);
  final SecretProtector protector;
  final KeyInspector inspector;

  Future<PreparedCredential> prepare(
    AuthenticationInput input, {
    required String credentialId,
    CredentialCancellation? cancellation,
  }) async {
    if (!isCanonicalUuid(credentialId)) {
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.authentication,
      );
    }
    cancellation?.check();
    final plaintext = switch (input) {
      PasswordInput() => Uint8List.fromList(utf8.encode(input.password)),
      PrivateKeyInput() => Uint8List.fromList(input.bytes),
    };
    Uint8List? encrypted;
    try {
      KeyInspection? inspection;
      if (input is PrivateKeyInput) {
        inspection = await inspector.inspect(
          plaintext,
          passphrase: input.passphrase,
          cancellation: cancellation,
        );
        cancellation?.check();
      }
      try {
        encrypted = await protector.protect(
          plaintext,
          'credential.v1:$credentialId',
        );
        if (encrypted.isEmpty || encrypted.length > 2 * 1024 * 1024) {
          throw const OperationFailure(FailureCode.protectionUnavailable);
        }
      } catch (_) {
        throw const OperationFailure(FailureCode.protectionUnavailable);
      }
      cancellation?.check();
      // Own our copy even if an adapter returns a shared buffer.
      return PreparedCredential._(
        input is PasswordInput ? AuthKind.password : AuthKind.privateKey,
        Uint8List.fromList(encrypted),
        inspection,
      );
    } finally {
      plaintext.fillRange(0, plaintext.length, 0);
      encrypted?.fillRange(0, encrypted.length, 0);
    }
  }
}

final class ValidatedProfileFields {
  const ValidatedProfileFields({
    required this.displayName,
    required this.originalHost,
    required this.normalizedHost,
    required this.port,
    required this.username,
    required this.endpointId,
  });
  final String displayName, originalHost, normalizedHost, username, endpointId;
  final int port;
}

final _dnsLabel = RegExp(r'^[a-zA-Z0-9](?:[a-zA-Z0-9-]*[a-zA-Z0-9])?$');
final _forbiddenUser = RegExp(r'[\s\p{Cc}\p{Cf}]', unicode: true);

ValidatedProfileFields validateProfileFields(ProfileDraft draft) =>
    validateProfileValues(
      displayName: draft.displayName,
      host: draft.host,
      port: draft.port,
      username: draft.username,
    );

ValidatedProfileFields validateProfileValues({
  required String displayName,
  required String host,
  int? port,
  required String username,
}) {
  final effectivePort = port ?? 22;
  final name = displayName.trim();
  if (!isWellFormedUnicode(name) || name.isEmpty || name.runes.length > 100) {
    throw const OperationFailure(
      FailureCode.invalidArgument,
      field: OperationField.displayName,
    );
  }
  final normalized = normalizeHost(host);
  if (effectivePort < 1 || effectivePort > 65535) {
    throw const OperationFailure(
      FailureCode.invalidArgument,
      field: OperationField.port,
    );
  }
  if (!isWellFormedUnicode(username) ||
      username.isEmpty ||
      username.runes.length > 255 ||
      _forbiddenUser.hasMatch(username)) {
    throw const OperationFailure(
      FailureCode.invalidArgument,
      field: OperationField.username,
    );
  }
  final digest = SHA256Digest().process(
    utf8.encode(jsonEncode([normalized, effectivePort])),
  );
  return ValidatedProfileFields(
    displayName: name,
    originalHost: host,
    normalizedHost: normalized,
    port: effectivePort,
    username: username,
    endpointId: digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
  );
}

String normalizeHost(String input) {
  const failure = OperationFailure(
    FailureCode.invalidArgument,
    field: OperationField.host,
  );
  if (input.isEmpty ||
      input.length > 253 ||
      !isWellFormedUnicode(input) ||
      RegExp(r'[\s\x00-\x20\x7f%/\\@?#]').hasMatch(input))
    throw failure;
  if (input.startsWith('[') && input.endsWith(']')) {
    final ipv6 = InternetAddress.tryParse(input.substring(1, input.length - 1));
    if (ipv6 == null || ipv6.type != InternetAddressType.IPv6) throw failure;
    return InternetAddress.fromRawAddress(
      ipv6.rawAddress,
      type: ipv6.type,
    ).address.toLowerCase();
  }
  if (input.contains('[') || input.contains(']')) throw failure;
  final ip = InternetAddress.tryParse(input);
  if (ip != null)
    return InternetAddress.fromRawAddress(
      ip.rawAddress,
      type: ip.type,
    ).address.toLowerCase();
  if (input.contains(':')) throw failure;
  final dns = input.endsWith('.')
      ? input.substring(0, input.length - 1)
      : input;
  if (dns
      .split('.')
      .any((p) => p.isEmpty || p.length > 63 || !_dnsLabel.hasMatch(p)))
    throw failure;
  return dns.toLowerCase();
}
