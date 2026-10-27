import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_release.dart';
import 'package:serverdeck_protocol/validation.dart';

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

  /// Identity belongs to the caller's real pipe worker; no claimed role/PID.
  VerifiedBundlePeer verifyPeer(
    RetainedProcessIdentity identity,
    String expectedOwnerSid,
  ) => VerifiedBundlePeer._(
    _bindPeer(
      manifest.appRoot,
      _manifestHash,
      manifest.sha256,
      identity,
      expectedOwnerSid,
    ),
  );
}

/// Separate format3 bundle/proof types cannot authorize a format2 composition.
final class TrustedBuildBundle {
  TrustedBuildBundle._(this.manifest, this._manifestHash);
  final TrustedBuildManifest manifest;
  final String _manifestHash;

  /// Launch metadata from this actual verified bundle. No caller path, token
  /// export or shell command is accepted or generated.
  Map<String, Object?> mcpConfiguration(String grantId) {
    requireUuid(grantId);
    final root = manifest.appRoot,
        command = p.join(manifest.appRoot, 'mcp.exe');
    requireSafePath(root, command);
    if (_digest(_manifestBytes(p.join(root, 'foundation.manifest.json'))) !=
            _manifestHash ||
        fileSha256(command) != manifest.sha256['mcp.exe'] ||
        _digest(_manifestBytes(p.join(root, 'foundation.manifest.json'))) !=
            _manifestHash)
      throw StateError('INCOMPATIBLE');
    return {
      'command': command,
      'args': ['--app-root', root, '--grant-id', grantId],
    };
  }

  VerifiedExecutorRelease loadExecutorRelease() {
    final expected = manifest.sha256['executor-release.json'];
    if (expected == null) throw StateError('EXECUTOR_UNAVAILABLE');
    final root = manifest.appRoot;
    final path = p.join(root, 'executor-release.json');
    void verify() {
      requireSafePath(root, path);
      if (fileSha256(path) != expected ||
          _digest(_manifestBytes(p.join(root, 'foundation.manifest.json'))) !=
              _manifestHash)
        throw StateError('INCOMPATIBLE');
    }

    verify();
    final reader = File(path).openSync();
    late final ExecutorRelease release;
    try {
      final bytes = reader.readSync(64 * 1024 + 1);
      release = ExecutorRelease.fromJson(
        StrictCodec().decode(bytes, maxBytes: 64 * 1024),
      );
    } finally {
      reader.closeSync();
    }
    verify();
    return VerifiedExecutorRelease._(release, verify);
  }

  VerifiedTrustedBundlePeer verifyPeer(
    RetainedProcessIdentity identity,
    String expectedOwnerSid,
  ) => VerifiedTrustedBundlePeer._(
    _bindPeer(
      manifest.appRoot,
      _manifestHash,
      manifest.sha256,
      identity,
      expectedOwnerSid,
    ),
  );
}

/// Only a verified format3 manifest can create this descriptor. A caller JSON
/// parser cannot mint it; each use rechecks its manifest/file binding.
final class VerifiedExecutorRelease {
  VerifiedExecutorRelease._(this._release, this._verify);
  final ExecutorRelease _release;
  final void Function() _verify;
  ExecutorRelease get descriptor {
    _verify();
    return _release;
  }

  void revalidate() => _verify();
}

/// Private construction binds format2 metadata to genuine retained identity.
/// The caller retains/ultimately closes the identity; no ownership swap.
final class VerifiedBundlePeer {
  VerifiedBundlePeer._(this._binding);
  final _PeerBinding _binding;
  BundlePeerRole get role => _binding.role;
  void revalidate() => _binding.revalidate();
}

/// Format3 only. There is no public constructor or conversion to an old proof.
final class VerifiedTrustedBundlePeer {
  VerifiedTrustedBundlePeer._(this._binding);
  final _PeerBinding _binding;
  BundlePeerRole get role => _binding.role;
  void revalidate() => _binding.revalidate();
}

_PeerBinding _bindPeer(
  String root,
  String manifestHash,
  Map<String, String> hashes,
  RetainedProcessIdentity identity,
  String ownerSid,
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
    final binding = _PeerBinding(
      root,
      manifestHash,
      identity,
      ownerSid,
      name,
      hashes[name]!,
      role,
    );
    binding.revalidate();
    return binding;
  } catch (_) {
    throw StateError('UNAUTHORIZED');
  }
}

// Shared actual hash/path/retained-handle checks, with only fixed constructors
// above supplying verified metadata. Neither JSON nor a callback chooses role.
final class _PeerBinding {
  _PeerBinding(
    this._root,
    this._manifestHash,
    this._identity,
    this._ownerSid,
    this._name,
    this._expectedHash,
    this._role,
  );
  final String _root, _manifestHash, _ownerSid, _name, _expectedHash;
  final RetainedProcessIdentity _identity;
  final BundlePeerRole _role;
  BundlePeerRole get role {
    revalidate();
    return _role;
  }

  void revalidate() {
    try {
      if (currentUserSid() != _ownerSid) throw StateError('UNAUTHORIZED');
      requireSafePath(_root, _root);
      final manifestPath = p.join(_root, 'foundation.manifest.json');
      requireSafePath(_root, manifestPath);
      if (_digest(_manifestBytes(manifestPath)) != _manifestHash)
        throw StateError('UNAUTHORIZED');
      final path = p.join(_root, _name);
      requireSafePath(_root, path);
      verifyProcessImage(_identity, _ownerSid, path, _expectedHash);
    } catch (_) {
      throw StateError('UNAUTHORIZED');
    }
  }
}

final class _ManifestSource {
  const _ManifestSource(this.root, this.bytes, this.hash);
  final String root, hash;
  final List<int> bytes;
}

_ManifestSource _readManifest(String appRoot) {
  if (!Platform.isWindows ||
      Abi.current() != Abi.windowsX64 ||
      !p.isAbsolute(appRoot))
    throw StateError('PREREQUISITE_UNAVAILABLE');
  final root = p.normalize(appRoot);
  requireSafePath(root, root);
  final path = p.join(root, 'foundation.manifest.json');
  requireSafePath(root, path);
  final bytes = _manifestBytes(path);
  return _ManifestSource(root, bytes, _digest(bytes));
}

void _verifyContents(
  _ManifestSource source,
  String declaredRoot,
  Map<String, String> hashes,
) {
  if (!p.isAbsolute(declaredRoot) ||
      !p.equals(p.normalize(declaredRoot), source.root))
    throw StateError('INCOMPATIBLE');
  for (final entry in hashes.entries) {
    final path = p.join(source.root, entry.key);
    requireSafePath(source.root, path);
    if (fileSha256(path) != entry.value) throw StateError('INCOMPATIBLE');
  }
  // Same bound and exact bytes before/after all four actual artifact hashes.
  if (_digest(
        _manifestBytes(p.join(source.root, 'foundation.manifest.json')),
      ) !=
      source.hash)
    throw StateError('INCOMPATIBLE');
}

Never _verificationFailed(Object error) {
  if (error is FormatException) throw StateError('INCOMPATIBLE');
  if (error is StateError &&
      (error.message == 'INCOMPATIBLE' ||
          error.message == 'PREREQUISITE_UNAVAILABLE'))
    throw error;
  throw StateError('PREREQUISITE_UNAVAILABLE');
}

Future<McpBuildBundle> verifyMcpBuildBundle(
  String appRoot, {
  bool testOnly = false,
}) async {
  try {
    final source = _readManifest(appRoot);
    final manifest = McpBuildManifest.fromJson(
      StrictCodec().decode(source.bytes),
      testOnly: testOnly,
    );
    _verifyContents(source, manifest.appRoot, manifest.sha256);
    return McpBuildBundle._(manifest, source.hash);
  } catch (error) {
    _verificationFailed(error);
  }
}

Future<TrustedBuildBundle> verifyTrustedBuildBundle(
  String appRoot, {
  bool testOnly = false,
}) async {
  try {
    final source = _readManifest(appRoot);
    final manifest = TrustedBuildManifest.fromJson(
      StrictCodec().decode(source.bytes),
      testOnly: testOnly,
    );
    _verifyContents(source, manifest.appRoot, manifest.sha256);
    return TrustedBuildBundle._(manifest, source.hash);
  } catch (error) {
    _verificationFailed(error);
  }
}
