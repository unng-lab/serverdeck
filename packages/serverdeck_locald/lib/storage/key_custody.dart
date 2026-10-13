import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/profile_validation.dart';
import 'package:serverdeck_windows/security.dart';

/// A keyed receipt digest protects access secrets against offline guessing.
/// This material never encrypts ordinary workspace records.
class ReceiptKeyMaterial {
  ReceiptKeyMaterial._(
    this._key,
    List<int> wrapper,
    this.workspaceId,
    this.receiptKeyId,
    this.ownerSid,
  ) : wrapper = List<int>.unmodifiable(wrapper);
  final Uint8List _key;
  final List<int> wrapper;
  final String workspaceId, receiptKeyId, ownerSid;
  bool _closed = false;
  void close() {
    _closed = true;
    _key.fillRange(0, _key.length, 0);
  }
}

class KeyCustody {
  KeyCustody(this.protection, this.ownerSid);
  final UserProtection protection;
  final String ownerSid;
  final _codec = StrictCodec();
  List<int> get _receiptEntropy =>
      utf8.encode('ServerDeckNext\nv1\ndefault\n$ownerSid\nreceipt');

  void _ids(Iterable<String> ids) {
    try {
      for (final id in ids) {
        requireUuid(id);
      }
    } on FormatException {
      throw StateError('STORAGE_BLOCKED');
    }
    if (!RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(ownerSid)) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  void _material(ReceiptKeyMaterial material) {
    _ids([material.workspaceId, material.receiptKeyId]);
    if (material._closed || material.ownerSid != ownerSid) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<ReceiptKeyMaterial> createReceiptKey(
    String workspaceId,
    String receiptKeyId,
  ) async {
    _ids([workspaceId, receiptKeyId]);
    final random = Random.secure();
    final key = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    final cleartext = Uint8List.fromList(
      _codec.encode({
        'format': 1,
        'product': 'serverdeck-next',
        'workspaceId': workspaceId,
        'receiptKeyId': receiptKeyId,
        'ownerSid': ownerSid,
        'receiptKey': base64.encode(key),
      }, maxBytes: 8192),
    );
    try {
      final wrapper = await protection.protect(cleartext, _receiptEntropy);
      if (wrapper.isEmpty || wrapper.length > 16384) {
        throw StateError('STORAGE_BLOCKED');
      }
      return ReceiptKeyMaterial._(
        key,
        wrapper,
        workspaceId,
        receiptKeyId,
        ownerSid,
      );
    } catch (_) {
      key.fillRange(0, key.length, 0);
      throw StateError('STORAGE_BLOCKED');
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<ReceiptKeyMaterial> openReceiptKey(
    List<int> wrapper,
    String workspaceId,
    String receiptKeyId,
  ) async {
    _ids([workspaceId, receiptKeyId]);
    List<int>? cleartext;
    Uint8List? key;
    try {
      if (wrapper.isEmpty || wrapper.length > 16384) {
        throw StateError('STORAGE_BLOCKED');
      }
      cleartext = await protection.unprotect(wrapper, _receiptEntropy);
      final value = _codec.decode(cleartext, maxBytes: 8192);
      requireFields(value, {
        'format',
        'product',
        'workspaceId',
        'receiptKeyId',
        'ownerSid',
        'receiptKey',
      });
      if (value['format'] is! int || value['format'] != 1) {
        throw StateError('INCOMPATIBLE');
      }
      if (value['product'] != 'serverdeck-next' ||
          value['workspaceId'] != workspaceId ||
          value['receiptKeyId'] != receiptKeyId ||
          value['ownerSid'] != ownerSid ||
          value['receiptKey'] is! String) {
        throw StateError('STORAGE_BLOCKED');
      }
      key = Uint8List.fromList(base64.decode(value['receiptKey'] as String));
      if (key.length != 32 || base64.encode(key) != value['receiptKey']) {
        throw StateError('STORAGE_BLOCKED');
      }
      return ReceiptKeyMaterial._(
        key,
        wrapper,
        workspaceId,
        receiptKeyId,
        ownerSid,
      );
    } catch (error) {
      key?.fillRange(0, key.length, 0);
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      cleartext?.fillRange(0, cleartext.length, 0);
    }
  }

  Future<String> receiptDigest(
    ReceiptKeyMaterial material,
    Map<String, Object?> validatedInput,
  ) async {
    _material(material);
    final bytes = Uint8List.fromList(_codec.canonical(validatedInput));
    final key = SecretKeyData(
      Uint8List.fromList(material._key),
      overwriteWhenDestroyed: true,
    );
    try {
      final mac = await Hmac.sha256().calculateMac(bytes, secretKey: key);
      _material(material);
      return base64.encode(mac.bytes);
    } finally {
      key.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Coordinator registration is synchronous, before its first async wait.
  String receiptDigestSync(
    ReceiptKeyMaterial material,
    Map<String, Object?> validatedInput,
  ) {
    _material(material);
    final bytes = Uint8List.fromList(_codec.canonical(validatedInput));
    final key = SecretKeyData(
      Uint8List.fromList(material._key),
      overwriteWhenDestroyed: true,
    );
    try {
      return base64.encode(
        DartHmac.sha256()
            .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
            .bytes,
      );
    } finally {
      key.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, Object?>> createWorkspaceManifest(
    ReceiptKeyMaterial material,
  ) async {
    _material(material);
    return {
      'product': 'serverdeck-next',
      'schema': 1,
      'workspaceId': material.workspaceId,
      'receiptKeyId': material.receiptKeyId,
      'ownerSid': ownerSid,
    };
  }

  Future<void> verifyWorkspaceManifest(
    Map<String, Object?> manifest,
    ReceiptKeyMaterial material,
  ) async {
    try {
      _material(material);
      requireFields(manifest, {
        'product',
        'schema',
        'workspaceId',
        'receiptKeyId',
        'ownerSid',
      });
      _codec.encode(manifest, maxBytes: 4096);
      if (manifest['schema'] is! int || manifest['schema'] != 1) {
        throw StateError('INCOMPATIBLE');
      }
      final expected = await createWorkspaceManifest(material);
      if (expected.entries.any((entry) => manifest[entry.key] != entry.value)) {
        throw StateError('STORAGE_BLOCKED');
      }
    } catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  List<int> _credentialEntropy(
    String workspaceId,
    String profileId,
    String credentialId,
  ) {
    _ids([workspaceId, profileId, credentialId]);
    return utf8.encode(
      'ServerDeckNext\nv1\n$workspaceId\n$profileId\n$credentialId\ncredential',
    );
  }

  Future<String> wrapCredential(
    String workspaceId,
    String profileId,
    String credentialId,
    Map<String, Object?> action,
  ) async {
    final entropy = _credentialEntropy(workspaceId, profileId, credentialId);
    final normalized = normalizeCredential(action);
    if (normalized['action'] != 'replace')
      throw const FormatException('VALIDATION');
    final cleartext = Uint8List.fromList(
      _codec.encode({
        'version': 1,
        'workspaceId': workspaceId,
        'profileId': profileId,
        'credentialId': credentialId,
        ...normalized..remove('action'),
      }, maxBytes: 256 * 1024),
    );
    try {
      final bytes = await protection.protect(cleartext, entropy);
      if (bytes.isEmpty || bytes.length > 256 * 1024) {
        throw StateError('STORAGE_BLOCKED');
      }
      return base64.encode(bytes);
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    } finally {
      cleartext.fillRange(0, cleartext.length, 0);
    }
  }

  Future<Map<String, Object?>> openCredential(
    String blob,
    String workspaceId,
    String profileId,
    String credentialId,
  ) async {
    final entropy = _credentialEntropy(workspaceId, profileId, credentialId);
    List<int>? cleartext;
    try {
      if (blob.isEmpty || blob.length > ((256 * 1024 + 2) ~/ 3) * 4)
        throw StateError('STORAGE_BLOCKED');
      final bytes = base64.decode(blob);
      if (bytes.isEmpty ||
          bytes.length > 256 * 1024 ||
          base64.encode(bytes) != blob)
        throw StateError('STORAGE_BLOCKED');
      cleartext = await protection.unprotect(bytes, entropy);
      final value = _codec.decode(cleartext, maxBytes: 256 * 1024);
      if (value['version'] is! int || value['version'] != 1)
        throw StateError('INCOMPATIBLE');
      if (value['workspaceId'] != workspaceId ||
          value['profileId'] != profileId ||
          value['credentialId'] != credentialId) {
        throw StateError('STORAGE_BLOCKED');
      }
      requireFields(
        value,
        {'version', 'workspaceId', 'profileId', 'credentialId', 'kind'},
        value['kind'] == 'password'
            ? {'password'}
            : {'privateKey', 'passphrase'},
      );
      final action = Map<String, Object?>.from(value)
        ..remove('version')
        ..remove('workspaceId')
        ..remove('profileId')
        ..remove('credentialId');
      final checked = normalizeCredential({'action': 'replace', ...action})
        ..remove('action');
      return checked;
    } catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      cleartext?.fillRange(0, cleartext.length, 0);
    }
  }
}
