import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_windows/build_bundle.dart';
import 'package:serverdeck_windows/mcp_build_bundle.dart';
import 'package:serverdeck_windows/security.dart';
export 'package:serverdeck_windows/build_bundle.dart' show verifyBuildBundle;

String? _loadedIdentity;
Future<void>? _loading;

final class _RuntimeConflict {
  const _RuntimeConflict();
}

Future<void> _load(String identity, String root) async {
  if (_loadedIdentity != null && _loadedIdentity != identity)
    throw const _RuntimeConflict();
  if (_loading == null) {
    _loadedIdentity = identity;
    // A synchronous native initialization failure must also remain sticky.
    _loading = Future<void>.sync(
      () => Isar.initializeIsarCore(
        libraries: {Abi.windowsX64: p.join(root, 'libisar.dll')},
        download: false,
      ),
    );
  }
  await _loading;
}

/// Verify the complete bundle before native loading or workspace writes.
Future<BuildManifest> initializeNativeRuntime(
  String appRoot, {
  bool testOnly = false,
}) async {
  try {
    final manifest = await verifyBuildBundle(appRoot, testOnly: testOnly);
    final root = p.normalize(appRoot);
    final identity =
        'format1\n$root\n${manifest.buildId}\n${manifest.testOnly}\n${manifest.sha256['libisar.dll']}';
    await _load(identity, root);
    return manifest;
  } on _RuntimeConflict {
    throw StateError('INCOMPATIBLE');
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

/// Explicit format2 native entry. The normal legacy bootstrap never selects it.
/// Actual current locald image proof precedes DLL loading; no role/PID override.
Future<McpBuildBundle> initializeMcpNativeRuntime(
  String appRoot, {
  bool testOnly = false,
}) async {
  final bundle = await verifyMcpBuildBundle(appRoot, testOnly: testOnly);
  RetainedProcessIdentity? self;
  try {
    late final VerifiedBundlePeer proof;
    try {
      self = RetainedProcessIdentity.open(pid);
      proof = bundle.verifyPeer(self, currentUserSid());
      if (proof.role != BundlePeerRole.locald) throw StateError('UNAUTHORIZED');
      proof.revalidate();
    } catch (_) {
      throw StateError('UNAUTHORIZED');
    }
    final root = p.normalize(appRoot), manifest = bundle.manifest;
    final identity =
        'format2\n$root\n${manifest.buildId}\n${manifest.testOnly}\n${manifest.sha256['libisar.dll']}';
    try {
      await _load(identity, root);
    } on _RuntimeConflict {
      throw StateError('INCOMPATIBLE');
    } catch (_) {
      throw StateError('PREREQUISITE_UNAVAILABLE');
    }
    proof.revalidate();
    return bundle;
  } finally {
    self?.close();
  }
}
