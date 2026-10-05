import 'dart:convert';

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
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
      'password' => SshCredential.password(value['material']),
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

class OsCredentialStore implements CredentialStore {
  OsCredentialStore();
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
      final result = CredRead(PCWSTR(target), CRED_TYPE_GENERIC, output);
      if (!result.value) {
        if (result.error == ERROR_NOT_FOUND) {
          return null;
        }
        throw StateError('Credential Manager read failed: ${result.error}');
      }
      final credential = output.value.ref;
      final raw = utf8.decode(
        credential.CredentialBlob.asTypedList(credential.CredentialBlobSize),
      );
      try {
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
    // Generic credentials cap each blob at 5*512 bytes. Large keys must use a
    // future protected-envelope adapter; never silently fall back to plaintext.
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
      final result = CredWrite(native, 0);
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
      final result = CredDelete(PCWSTR(target), CRED_TYPE_GENERIC);
      if (!result.value && result.error != ERROR_NOT_FOUND) {
        throw StateError('Credential Manager delete failed: ${result.error}');
      }
    } finally {
      calloc.free(target);
    }
  }
}
