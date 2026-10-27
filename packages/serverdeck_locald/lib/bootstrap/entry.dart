import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import 'native_runtime.dart';

/// Fixed production launch contract. No endpoint, custody or path overrides.
class LocaldArguments {
  LocaldArguments._(this.appRoot);
  final String appRoot;

  factory LocaldArguments.parse(List<String> arguments) {
    if (arguments.length != 4) throw StateError('PREREQUISITE_UNAVAILABLE');
    final values = <String, String>{};
    for (var i = 0; i < arguments.length; i += 2) {
      final name = arguments[i], value = arguments[i + 1];
      if (!{'--workspace', '--app-root'}.contains(name) ||
          values.containsKey(name) ||
          value.isEmpty ||
          value.contains('\u0000')) {
        throw StateError('PREREQUISITE_UNAVAILABLE');
      }
      values[name] = value;
    }
    final root = values['--app-root'];
    if (values['--workspace'] != 'default' ||
        root == null ||
        root.length > 32767 ||
        !p.isAbsolute(root)) {
      throw StateError('PREREQUISITE_UNAVAILABLE');
    }
    return LocaldArguments._(p.normalize(root));
  }
}

class LocaldEnvironment {
  LocaldEnvironment._(
    this.arguments,
    this.manifest,
    this.localAppData,
    this.sid,
  );
  final LocaldArguments arguments;
  final BuildManifest manifest;
  final String localAppData, sid;

  /// Called by the production executable before namespace/private-file work.
  static Future<LocaldEnvironment> verify(LocaldArguments arguments) async {
    final localAppData = Platform.environment['LOCALAPPDATA'];
    if (localAppData == null || !p.isAbsolute(localAppData)) {
      throw StateError('PREREQUISITE_UNAVAILABLE');
    }
    requireSafePath(localAppData, localAppData);
    final sid = currentUserSid();
    final manifest = await verifyBuildBundle(arguments.appRoot);
    final identity = RetainedProcessIdentity.open(pid);
    try {
      verifyProcessImage(
        identity,
        sid,
        p.join(arguments.appRoot, 'locald.exe'),
        manifest.sha256['locald.exe']!,
      );
    } catch (_) {
      throw StateError('INCOMPATIBLE');
    } finally {
      identity.close();
    }
    await initializeNativeRuntime(arguments.appRoot);
    return LocaldEnvironment._(
      arguments,
      manifest,
      p.normalize(localAppData),
      sid,
    );
  }
}
