import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

// Test-only build selection. Product code loads only its bundle manifest DLL.
String nativeArtifactForTest() {
  final root = p.normalize(p.absolute('../..'));
  final result = Process.runSync('pwsh', [
    '-NoProfile',
    '-File',
    p.join(root, 'tools', 'resolve-native-artifact.ps1'),
  ], workingDirectory: root);
  if (result.exitCode != 0) {
    throw StateError('NATIVE_TEST_ARTIFACT_SELECTION_FAILED: ${result.stderr}');
  }
  final selection = jsonDecode(result.stdout as String) as Map<String, dynamic>;
  final dll = selection['dll'] as String;
  if (!p.isAbsolute(dll) || !File(dll).existsSync()) {
    throw StateError('NATIVE_TEST_ARTIFACT_MISSING');
  }
  return dll;
}
