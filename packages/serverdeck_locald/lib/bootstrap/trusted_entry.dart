import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/mcp_build_bundle.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import 'entry.dart' show LocaldArguments;
import 'native_runtime.dart';

final class TrustedLocaldEnvironment {
  TrustedLocaldEnvironment._(
    this.arguments,
    this.bundle,
    this.localAppData,
    this.sid,
  );
  final LocaldArguments arguments;
  final TrustedBuildBundle bundle;
  final String localAppData, sid;
  static Future<TrustedLocaldEnvironment> verify(
    LocaldArguments arguments,
  ) async {
    final root = Platform.environment['LOCALAPPDATA'];
    if (root == null || !p.isAbsolute(root))
      throw StateError('PREREQUISITE_UNAVAILABLE');
    requireSafePath(root, root);
    final sid = currentUserSid(),
        bundle = await verifyTrustedBuildBundle(arguments.appRoot);
    final identity = RetainedProcessIdentity.open(pid);
    try {
      verifyProcessImage(
        identity,
        sid,
        p.join(arguments.appRoot, 'locald.exe'),
        bundle.manifest.sha256['locald.exe']!,
      );
    } catch (_) {
      throw StateError('INCOMPATIBLE');
    } finally {
      identity.close();
    }
    await initializeTrustedNativeRuntime(arguments.appRoot);
    return TrustedLocaldEnvironment._(
      arguments,
      bundle,
      p.normalize(root),
      sid,
    );
  }
}
