import 'dart:ffi';
import 'dart:io';

import 'package:cryptography/dart.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/verified_release.dart';
import 'package:serverdeck_engine/platform/ports.dart'
    show VerifiedAppConfiguration;
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_release.dart';
import 'package:serverdeck_protocol/validation.dart';

import 'paths.dart';
import 'process.dart';
import 'security.dart';

String _digest(List<int> bytes) => const DartSha256()
    .hashSync(bytes)
    .bytes
    .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
    .join();

List<int> _readBounded(String path, int maximum) {
  final reader = File(path).openSync();
  try {
    final bytes = reader.readSync(maximum + 1);
    if (bytes.isEmpty || bytes.length > maximum)
      throw StateError('INCOMPATIBLE');
    return bytes;
  } finally {
    reader.closeSync();
  }
}

/// Verified format4 artifacts, without a store, process role or owner authority.
/// Only actual retained application identity can produce a peer below.
final class EmbeddedBuildBundle implements VerifiedAppConfiguration {
  EmbeddedBuildBundle._(this.manifest, this._root, this._manifestHash);
  final EmbeddedBuildManifest manifest;
  final String _root, _manifestHash;
  String get appRoot => _root;
  String get buildId => manifest.buildId;
  bool _retired = false;
  String get _manifestPath => p.join(_root, 'foundation.manifest.json');

  void _manifest() {
    if (_retired) throw StateError('INCOMPATIBLE');
    try {
      requireSafePath(_root, _root);
      requireSafePath(_root, _manifestPath);
      if (_digest(_readBounded(_manifestPath, 16 * 1024)) != _manifestHash)
        throw StateError('INCOMPATIBLE');
    } catch (_) {
      _retired = true;
      throw StateError('INCOMPATIBLE');
    }
  }

  /// Any observed failure permanently retires this captured artifact binding.
  /// Restoring files does not revive a previously failed host generation.
  void revalidate() {
    if (_retired) throw StateError('INCOMPATIBLE');
    try {
      _manifest();
      for (final entry in manifest.sha256.entries) {
        final path = p.join(_root, entry.key);
        requireSafePath(_root, path);
        if (fileSha256(path) != entry.value) throw StateError('INCOMPATIBLE');
      }
      _manifest();
    } catch (_) {
      _retired = true;
      throw StateError('INCOMPATIBLE');
    }
  }

  /// Same executable for both processes; arguments cannot mint an owner role.
  Map<String, Object?> mcpConfiguration(String grantId) {
    requireUuid(grantId);
    revalidate();
    return {
      'command': p.join(_root, 'serverdeck.exe'),
      'args': ['--mcp-stdio', '--grant-id', grantId],
    };
  }

  VerifiedApplicationPeer verifyPeer(
    RetainedProcessIdentity identity,
    String expectedOwnerSid,
  ) {
    final proof = VerifiedApplicationPeer._(this, identity, expectedOwnerSid);
    proof.revalidate();
    return proof;
  }

  VerifiedExecutorRelease loadExecutorRelease() {
    revalidate();
    if (!manifest.sha256.containsKey('executor-release.json'))
      throw StateError('EXECUTOR_UNAVAILABLE');
    final path = p.join(_root, 'executor-release.json');
    try {
      requireSafePath(_root, path);
      final bytes = _readBounded(path, 64 * 1024);
      if (_digest(bytes) != manifest.sha256['executor-release.json'])
        throw StateError('INCOMPATIBLE');
      final release = ExecutorRelease.fromJson(
        StrictCodec().decode(bytes, maxBytes: 64 * 1024),
      );
      revalidate();
      return _VerifiedRelease(release, revalidate);
    } catch (_) {
      _retired = true;
      throw StateError('INCOMPATIBLE');
    }
  }
}

final class _VerifiedRelease implements VerifiedExecutorRelease {
  _VerifiedRelease(this._descriptor, this._check);
  final ExecutorRelease _descriptor;
  final void Function() _check;
  @override
  ExecutorRelease get descriptor {
    _check();
    return _descriptor;
  }

  @override
  void revalidate() => _check();
}

/// Caller retains/closes the genuine process handle. No role, claimed PID or
/// decoder is accepted. Both app and stdio peers have only application identity.
final class VerifiedApplicationPeer {
  VerifiedApplicationPeer._(this._bundle, this._identity, this._ownerSid);
  final EmbeddedBuildBundle _bundle;
  final RetainedProcessIdentity _identity;
  final String _ownerSid;
  bool _retired = false;
  String get buildId {
    revalidate();
    return _bundle.manifest.buildId;
  }

  int get processId {
    revalidate();
    return _identity.pid;
  }

  String get ownerSid {
    revalidate();
    return _ownerSid;
  }

  /// A store runtime requires this exact bundle's actual current process.
  /// A peer from another copy with an equal buildId cannot substitute for it.
  void requireCurrentProcess(EmbeddedBuildBundle bundle) {
    if (!identical(_bundle, bundle) || _identity.pid != pid) {
      throw StateError('UNAUTHORIZED');
    }
    revalidate();
  }

  void revalidate() {
    if (_retired) throw StateError('UNAUTHORIZED');
    try {
      if (currentUserSid() != _ownerSid) throw StateError('UNAUTHORIZED');
      _bundle.revalidate();
      final path = p.join(_bundle._root, 'serverdeck.exe');
      requireSafePath(_bundle._root, path);
      verifyProcessImage(
        _identity,
        _ownerSid,
        path,
        _bundle.manifest.sha256['serverdeck.exe']!,
      );
      _bundle._manifest();
      _identity.revalidate();
    } catch (_) {
      _retired = true;
      throw StateError('UNAUTHORIZED');
    }
  }
}

Future<EmbeddedBuildBundle> verifyEmbeddedBuildBundle(
  String appRoot, {
  bool testOnly = false,
}) async {
  try {
    if (!Platform.isWindows ||
        Abi.current() != Abi.windowsX64 ||
        !p.isAbsolute(appRoot)) {
      throw StateError('PREREQUISITE_UNAVAILABLE');
    }
    final root = p.normalize(appRoot),
        path = p.join(p.normalize(appRoot), 'foundation.manifest.json');
    requireSafePath(root, root);
    requireSafePath(root, path);
    final bytes = _readBounded(path, 16 * 1024);
    final manifest = EmbeddedBuildManifest.fromJson(
      StrictCodec().decode(bytes, maxBytes: 16 * 1024),
      testOnly: testOnly,
    );
    if (!p.isAbsolute(manifest.appRoot) ||
        !p.equals(p.normalize(manifest.appRoot), root))
      throw StateError('INCOMPATIBLE');
    for (final entry in manifest.sha256.entries) {
      final artifact = p.join(root, entry.key);
      requireSafePath(root, artifact);
      if (fileSha256(artifact) != entry.value) throw StateError('INCOMPATIBLE');
    }
    requireSafePath(root, path);
    final manifestHash = _digest(bytes);
    if (_digest(_readBounded(path, 16 * 1024)) != manifestHash)
      throw StateError('INCOMPATIBLE');
    return EmbeddedBuildBundle._(manifest, root, manifestHash);
  } catch (error) {
    if (error is FormatException) throw StateError('INCOMPATIBLE');
    if (error is StateError &&
        const {
          'INCOMPATIBLE',
          'PREREQUISITE_UNAVAILABLE',
        }.contains(error.message))
      rethrow;
    throw StateError('PREREQUISITE_UNAVAILABLE');
  }
}
