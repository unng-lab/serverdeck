import 'dart:ffi';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_windows/build_bundle.dart';
export 'package:serverdeck_windows/build_bundle.dart' show verifyBuildBundle;

String? _loadedIdentity;
Future<void>? _loading;

/// Verify the complete bundle before native loading or workspace writes.
Future<BuildManifest> initializeNativeRuntime(
  String appRoot, {
  bool testOnly = false,
}) async {
  try {
    final manifest = await verifyBuildBundle(appRoot, testOnly: testOnly);
    final root = p.normalize(appRoot);
    final identity =
        '$root\n${manifest.buildId}\n${manifest.testOnly}\n${manifest.sha256['libisar.dll']}';
    if (_loadedIdentity != null && _loadedIdentity != identity)
      throw StateError('INCOMPATIBLE');
    if (_loading == null) {
      _loadedIdentity = identity;
      _loading = Isar.initializeIsarCore(
        libraries: {Abi.windowsX64: p.join(root, 'libisar.dll')},
        download: false,
      );
    }
    await _loading;
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
