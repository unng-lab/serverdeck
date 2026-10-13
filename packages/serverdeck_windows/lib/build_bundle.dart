import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_protocol/codec.dart';

import 'paths.dart';
import 'process.dart';

/// Verify bundle bytes without loading native code or creating private files.
Future<BuildManifest> verifyBuildBundle(
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
    final manifestPath = p.join(root, 'foundation.manifest.json');
    requireSafePath(root, manifestPath);
    final reader = await File(manifestPath).open();
    late final List<int> bytes;
    try {
      bytes = await reader.read(16 * 1024 + 1);
      if (bytes.length > 16 * 1024) throw StateError('INCOMPATIBLE');
    } finally {
      await reader.close();
    }
    final manifest = BuildManifest.fromJson(
      StrictCodec().decode(bytes),
      testOnly: testOnly,
    );
    if (!p.equals(p.normalize(manifest.appRoot), root) ||
        !p.isAbsolute(manifest.appRoot)) {
      throw StateError('INCOMPATIBLE');
    }
    for (final entry in manifest.sha256.entries) {
      final path = p.join(root, entry.key);
      requireSafePath(root, path);
      if (fileSha256(path) != entry.value) throw StateError('INCOMPATIBLE');
    }
    return manifest;
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
