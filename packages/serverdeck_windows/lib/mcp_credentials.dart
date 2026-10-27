import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_protocol/automation/values.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

import 'security.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');

final class _UnsupportedFormat {}

void _wipe(List<int>? bytes) {
  if (bytes == null) return;
  try {
    bytes.fillRange(0, bytes.length, 0);
  } catch (_) {
    _blocked();
  }
}

Uint8List _bytes(List<int> input, int max, {int? exact}) {
  if (input.isEmpty ||
      input.length > max ||
      exact != null && input.length != exact ||
      input.any((b) => b < 0 || b > 255)) {
    _blocked();
  }
  return Uint8List.fromList(input);
}

/// Immutable identity of an issued credential, unaffected by metadata revoke.
final class McpCredentialBinding {
  factory McpCredentialBinding({
    required String workspaceId,
    required String grantId,
    required String secretRef,
    required String ownerSid,
    required String issuedAt,
  }) {
    try {
      requireUuid(workspaceId);
      requireUuid(grantId);
      requireUuid(secretRef);
      automationTimestamp(issuedAt);
      if (!RegExp(r'^S-1-\d+(?:-\d+)+$').hasMatch(ownerSid)) _blocked();
      final result = McpCredentialBinding._(
        workspaceId,
        grantId,
        secretRef,
        ownerSid,
        issuedAt,
      );
      StrictCodec().encode(result._fields, maxBytes: 4096);
      return result;
    } catch (_) {
      _blocked();
    }
  }
  const McpCredentialBinding._(
    this.workspaceId,
    this.grantId,
    this.secretRef,
    this.ownerSid,
    this.issuedAt,
  );
  final String workspaceId, grantId, secretRef, ownerSid, issuedAt;

  Map<String, Object?> get _fields => {
    'workspaceId': workspaceId,
    'grantId': grantId,
    'secretRef': secretRef,
    'ownerSid': ownerSid,
    'issuedAt': issuedAt,
  };
  List<int> get _entropy => StrictCodec().canonical({
    'purpose': 'serverdeck-next-mcp-client-v1',
    ..._fields,
  });
}

/// Only encrypted wrapper bytes are public. Never serialize the private handle.
final class McpProtectedCredential {
  McpProtectedCredential._(List<int> wrapper, this.key)
    : wrapper = List<int>.unmodifiable(wrapper);
  final List<int> wrapper;
  final McpClientKey key;
}

/// Shared primitive for locald and verified bridge, with no filesystem or policy.
final class McpCredentialCustody {
  McpCredentialCustody(this.protection);
  final UserProtection protection;

  Future<McpProtectedCredential> create(McpCredentialBinding binding) async {
    Uint8List? raw;
    List<int>? clear;
    try {
      final rng = Random.secure();
      raw = Uint8List(32);
      for (var i = 0; i < raw.length; i++) {
        raw[i] = rng.nextInt(256);
      }
      clear = StrictCodec().canonical({
        'format': 1,
        'product': 'serverdeck-next-mcp-client',
        ...binding._fields,
        'clientSecret': base64.encode(raw),
      });
      // Retain the allocated bytes even when over limit, so finally can wipe
      // them. encode(maxBytes:) would throw before assigning its buffer here.
      if (clear.length > 4096) _blocked();
      final wrapper = _bytes(
        await protection.protect(clear, binding._entropy),
        16384,
      );
      return McpProtectedCredential._(wrapper, McpClientKey._(raw));
    } catch (_) {
      _blocked();
    } finally {
      raw?.fillRange(0, raw.length, 0);
      _wipe(clear);
    }
  }

  Future<McpClientKey> open(
    List<int> wrapper,
    McpCredentialBinding binding,
  ) async {
    List<int>? clear;
    Uint8List? raw;
    try {
      final input = _bytes(wrapper, 16384);
      clear = await protection.unprotect(input, binding._entropy);
      // Do not truncate invalid provider byte values via Uint8List conversion.
      if (clear.isEmpty ||
          clear.length > 4096 ||
          clear.any((b) => b < 0 || b > 255))
        _blocked();
      final value = StrictCodec().decode(clear, maxBytes: 4096);
      requireFields(value, {
        'format',
        'product',
        'workspaceId',
        'grantId',
        'secretRef',
        'ownerSid',
        'issuedAt',
        'clientSecret',
      });
      if (value['format'] is! int) _blocked();
      if (value['format'] != 1) throw _UnsupportedFormat();
      if (value['product'] != 'serverdeck-next-mcp-client' ||
          binding._fields.entries.any((e) => value[e.key] != e.value) ||
          value['clientSecret'] is! String)
        _blocked();
      final encoded = value['clientSecret'] as String;
      // A decoder can allocate/fill a partial secret and throw before returning
      // it. Validate exact32-byte canonical form, including unused bits, first.
      if (encoded.length != 44 ||
          !RegExp(r'^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$')
              .hasMatch(encoded)) {
        _blocked();
      }
      raw = base64.decode(encoded);
      if (raw.length != 32 || base64.encode(raw) != value['clientSecret'])
        _blocked();
      // Validate that the transferred provider buffer can be disposed before
      // allocating a handle that could otherwise be lost to a cleanup failure.
      _wipe(clear);
      clear = null;
      return McpClientKey._(raw);
    } catch (error) {
      if (error is _UnsupportedFormat) throw StateError('INCOMPATIBLE');
      _blocked();
    } finally {
      raw?.fillRange(0, raw.length, 0);
      _wipe(clear);
    }
  }
}

/// No key bytes getter, serialization or arbitrary signing API is exposed over IPC.
final class McpClientKey {
  McpClientKey._(List<int> key) : _key = Uint8List.fromList(key);
  final Uint8List _key;
  bool _closed = false;

  void _live() {
    if (_closed) _blocked();
  }

  Future<List<int>> mac(List<int> transcript) async {
    Uint8List? bytes;
    SecretKeyData? key;
    try {
      _live();
      bytes = _bytes(transcript, 4096);
      key = SecretKeyData(
        Uint8List.fromList(_key),
        overwriteWhenDestroyed: true,
      );
      final result = await Hmac.sha256().calculateMac(bytes, secretKey: key);
      _live();
      return List<int>.unmodifiable(result.bytes);
    } catch (_) {
      _blocked();
    } finally {
      key?.destroy();
      bytes?.fillRange(0, bytes.length, 0);
    }
  }

  Future<bool> verify(List<int> transcript, List<int> expected) async {
    Uint8List? comparison;
    try {
      _live();
      comparison = _bytes(expected, 32, exact: 32);
      final actual = await mac(transcript);
      _live();
      var difference = 0;
      for (var i = 0; i < 32; i++) {
        difference |= actual[i] ^ comparison[i];
      }
      return difference == 0;
    } catch (_) {
      _blocked();
    } finally {
      comparison?.fillRange(0, comparison.length, 0);
    }
  }

  void close() {
    _closed = true;
    _key.fillRange(0, _key.length, 0);
  }
}
