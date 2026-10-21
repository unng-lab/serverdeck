import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'paths.dart';
import 'process.dart';
import 'security.dart';

enum BundlePeerRole { owner, mcp, locald }

List<int> _manifestBytes(String path) {
  final reader = File(path).openSync();
  try {
    final bytes = reader.readSync(16 * 1024 + 1);
    if (bytes.length > 16 * 1024) throw StateError('INCOMPATIBLE');
    return bytes;
  } finally {
    reader.closeSync();
  }
}

String _digest(List<int> bytes) => const DartSha256()
    .hashSync(bytes)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0'))
    .join();

/// Verified operational metadata, not permission to initialize an old bootstrap
/// or authenticate a session. Construction never opens the private workspace.
final class McpBuildBundle {
  McpBuildBundle._(this.manifest, this._manifestHash);
  final McpBuildManifest manifest;
  final String _manifestHash;

  void _current() {
    final root = manifest.appRoot;
    requireSafePath(root, root);
    final path = p.join(root, 'foundation.manifest.json');
    requireSafePath(root, path);
    if (_digest(_manifestBytes(path)) != _manifestHash)
      throw StateError('UNAUTHORIZED');
  }

  /// Caller obtains PID from the actual pipe and owns the retained identity on
  /// its pipe worker. Neither a claimed PID nor a requested role is accepted.
  VerifiedBundlePeer verifyPeer(
    RetainedProcessIdentity identity,
    String expectedOwnerSid,
  ) {
    try {
      final name = switch (p.basename(identity.imagePath).toLowerCase()) {
        'serverdeck.exe' => 'serverdeck.exe',
        'mcp.exe' => 'mcp.exe',
        'locald.exe' => 'locald.exe',
        _ => throw StateError('UNAUTHORIZED'),
      };
      final role = switch (name) {
        'serverdeck.exe' => BundlePeerRole.owner,
        'mcp.exe' => BundlePeerRole.mcp,
        _ => BundlePeerRole.locald,
      };
      final proof = VerifiedBundlePeer._(
        this,
        identity,
        expectedOwnerSid,
        name,
        role,
      );
      proof.revalidate();
      return proof;
    } catch (_) {
      throw StateError('UNAUTHORIZED');
    }
  }
}

/// Private construction binds role to verified bytes and an actual retained
/// process. The caller retains/ultimately closes the identity; no ownership swap.
final class VerifiedBundlePeer {
  VerifiedBundlePeer._(
    this._bundle,
    this._identity,
    this._ownerSid,
    this._name,
    this._role,
  );
  final McpBuildBundle _bundle;
  final RetainedProcessIdentity _identity;
  final String _ownerSid, _name;
  final BundlePeerRole _role;

  BundlePeerRole get role {
    revalidate();
    return _role;
  }

  void revalidate() {
    try {
      if (currentUserSid() != _ownerSid) throw StateError('UNAUTHORIZED');
      _bundle._current();
      final root = _bundle.manifest.appRoot, path = p.join(root, _name);
      requireSafePath(root, path);
      verifyProcessImage(
        _identity,
        _ownerSid,
        path,
        _bundle.manifest.sha256[_name]!,
      );
    } catch (_) {
      throw StateError('UNAUTHORIZED');
    }
  }
}

Future<McpBuildBundle> verifyMcpBuildBundle(
  String appRoot, {
  bool testOnly = false,
}) async {
  try {
    if (!Platform.isWindows ||
        Abi.current() != Abi.windowsX64 ||
        !p.isAbsolute(appRoot))
      throw StateError('PREREQUISITE_UNAVAILABLE');
    final root = p.normalize(appRoot);
    requireSafePath(root, root);
    final path = p.join(root, 'foundation.manifest.json');
    requireSafePath(root, path);
    final bytes = _manifestBytes(path);
    final manifest = McpBuildManifest.fromJson(
      StrictCodec().decode(bytes),
      testOnly: testOnly,
    );
    if (!p.isAbsolute(manifest.appRoot) ||
        !p.equals(p.normalize(manifest.appRoot), root)) {
      throw StateError('INCOMPATIBLE');
    }
    for (final entry in manifest.sha256.entries) {
      final file = p.join(root, entry.key);
      requireSafePath(root, file);
      if (fileSha256(file) != entry.value) throw StateError('INCOMPATIBLE');
    }
    final bundle = McpBuildBundle._(manifest, _digest(bytes));
    // Re-read with the same bound: source bytes cannot silently change while
    // checking the executable hashes, and the proof keeps the original digest.
    if (_digest(_manifestBytes(path)) != bundle._manifestHash)
      throw StateError('INCOMPATIBLE');
    return bundle;
  } on FormatException {
    throw StateError('INCOMPATIBLE');
  } on StateError catch (error) {
    if (error.message == 'INCOMPATIBLE' ||
        error.message == 'PREREQUISITE_UNAVAILABLE')
      rethrow;
    throw StateError('PREREQUISITE_UNAVAILABLE');
  } catch (_) {
    throw StateError('PREREQUISITE_UNAVAILABLE');
  }
}
