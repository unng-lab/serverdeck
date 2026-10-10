import 'dart:convert';

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:meta/meta.dart' show visibleForTesting;
import 'package:win32/win32.dart';

class SshCredential {
  const SshCredential.password(this.material)
    : kind = 'password',
      passphrase = null;
  const SshCredential.key(this.material, {this.passphrase}) : kind = 'key';
  final String kind, material;
  final String? passphrase;
  // Only passed to the OS secure store, never profile/observation persistence.
  Map<String, dynamic> _secretFields() => {
    'kind': kind,
    'material': material,
    'passphrase': passphrase,
  };
  static SshCredential _decode(String raw) {
    final value = jsonDecode(raw);
    if (value is! Map ||
        value['material'] is! String ||
        (value['passphrase'] != null && value['passphrase'] is! String)) {
      throw const FormatException('Invalid protected credential');
    }
    return switch (value['kind']) {
      'password' when value['passphrase'] == null => SshCredential.password(
        value['material'],
      ),
      'key' => SshCredential.key(
        value['material'],
        passphrase: value['passphrase'],
      ),
      _ => throw const FormatException('Unsupported credential type'),
    };
  }

  @override
  String toString() => 'SshCredential($kind, protected)';
}

abstract interface class CredentialStore {
  Future<SshCredential?> read(String reference);
}

/// Native call boundary; buffers remain owned and freed by OsCredentialStore.
abstract interface class CredentialNativeApi {
  Win32Result<bool> read(
    Pointer<Utf16> target,
    Pointer<Pointer<CREDENTIAL>> output,
  );
  Win32Result<bool> write(Pointer<CREDENTIAL> credential);
  Win32Result<bool> delete(Pointer<Utf16> target);
}

class _WindowsCredentialApi implements CredentialNativeApi {
  const _WindowsCredentialApi();
  @override
  Win32Result<bool> read(
    Pointer<Utf16> target,
    Pointer<Pointer<CREDENTIAL>> output,
  ) => CredRead(PCWSTR(target), CRED_TYPE_GENERIC, output);
  @override
  Win32Result<bool> write(Pointer<CREDENTIAL> credential) =>
      CredWrite(credential, 0);
  @override
  Win32Result<bool> delete(Pointer<Utf16> target) =>
      CredDelete(PCWSTR(target), CRED_TYPE_GENERIC);
}

/// Calls apply independently; references are shared by the Windows account.
/// Concurrent callers have no FIFO/CAS guarantee. A later write may recreate a
/// deleted credential. A failure does not undo another caller's successful call.
class OsCredentialStore implements CredentialStore {
  OsCredentialStore() : _api = const _WindowsCredentialApi();
  @visibleForTesting
  OsCredentialStore.withNativeApi(this._api);
  final CredentialNativeApi _api;
  String _key(String reference) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows Credential Manager required');
    }
    if (!RegExp(r'^[a-z0-9_-]{1,80}$').hasMatch(reference)) {
      throw ArgumentError('Invalid credential reference');
    }
    return 'serverdeck-credential-$reference';
  }

  @override
  Future<SshCredential?> read(String reference) async {
    final target = _key(reference).toNativeUtf16();
    final output = calloc<Pointer<CREDENTIAL>>();
    try {
      final result = _api.read(target, output);
      if (!result.value) {
        if (result.error == ERROR_NOT_FOUND) {
          return null;
        }
        throw StateError('Credential Manager read failed: ${result.error}');
      }
      final credential = output.value.ref;
      try {
        final raw = utf8.decode(
          credential.CredentialBlob.asTypedList(credential.CredentialBlobSize),
        );
        return SshCredential._decode(raw);
      } on FormatException {
        throw const FormatException('Protected credential is invalid');
      }
    } finally {
      if (output.value != nullptr) {
        CredFree(output.value);
      }
      calloc.free(output);
      calloc.free(target);
    }
  }

  Future<void> write(String reference, SshCredential credential) async {
    final key = _key(reference);
    final bytes = utf8.encode(jsonEncode(credential._secretFields()));
    // Reject unsupported payloads before changing the stored credential.
    if (bytes.length > 2560) {
      throw ArgumentError('Credential exceeds 2560-byte Windows blob limit');
    }
    final target = key.toNativeUtf16();
    final native = calloc<CREDENTIAL>();
    final blob = calloc<Uint8>(bytes.length);
    try {
      blob.asTypedList(bytes.length).setAll(0, bytes);
      native.ref.Type = CRED_TYPE_GENERIC;
      native.ref.TargetName = PWSTR(target);
      native.ref.Persist = CRED_PERSIST_LOCAL_MACHINE;
      native.ref.CredentialBlobSize = bytes.length;
      native.ref.CredentialBlob = blob;
      final result = _api.write(native);
      if (!result.value) {
        throw StateError('Credential Manager write failed: ${result.error}');
      }
    } finally {
      blob.asTypedList(bytes.length).fillRange(0, bytes.length, 0);
      calloc.free(blob);
      calloc.free(native);
      calloc.free(target);
    }
  }

  Future<void> delete(String reference) async {
    final target = _key(reference).toNativeUtf16();
    try {
      final result = _api.delete(target);
      if (!result.value && result.error != ERROR_NOT_FOUND) {
        throw StateError('Credential Manager delete failed: ${result.error}');
      }
    } finally {
      calloc.free(target);
    }
  }
}
