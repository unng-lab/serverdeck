import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/build_manifest.dart';
import 'package:win32/win32.dart';

import 'build_bundle.dart';
import 'mcp_build_bundle.dart';
import 'discovery.dart';
import 'dpapi.dart';
import 'native_attributes.dart';
import 'paths.dart';
import 'process.dart';
import 'security.dart';

/// Verified metadata only; no Isar loader or private workspace access.
class ClientBootstrapEnvironment {
  ClientBootstrapEnvironment._(this.manifest, this.localAppData, this.sid);
  final BuildManifest manifest;
  final String localAppData, sid;

  static Future<ClientBootstrapEnvironment> verify() async {
    try {
      final root = p.dirname(Platform.resolvedExecutable);
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null || !p.isAbsolute(local))
        throw StateError('PREREQUISITE_UNAVAILABLE');
      requireSafePath(local, local);
      final manifest = await verifyBuildBundle(root);
      final sid = currentUserSid();
      final identity = RetainedProcessIdentity.open(pid);
      try {
        verifyProcessImage(
          identity,
          sid,
          p.join(root, 'serverdeck.exe'),
          manifest.sha256['serverdeck.exe']!,
        );
      } finally {
        identity.close();
      }
      return ClientBootstrapEnvironment._(manifest, local, sid);
    } on Object catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('PREREQUISITE_UNAVAILABLE');
    }
  }

  Future<DiscoveryDescriptor?> discovery() async {
    try {
      final directory = p.join(localAppData, 'ServerDeckNext', 'v1', 'runtime');
      final path = p.join(directory, 'default.discovery');
      requireSafePath(localAppData, path);
      if (queryLocalAttributes(directory) == null) return null;
      requireOwnerOnlyFileAcl(directory, sid);
      if (queryLocalAttributes(path) == null) return null;
      final bytes = await readProtectedFile(
        localAppData,
        path,
        sid,
        maxBytes: 16384,
      );
      return await DiscoveryCustody(
        DpapiProtection(),
        sid,
      ).unprotect(bytes, manifest.buildId);
    } on Object catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  String get localdPath => p.join(manifest.appRoot, 'locald.exe');

  /// A contender is harmless; launch does not confer namespace ownership.
  OwnedLocaldChild launch() =>
      _launchLocald(manifest.appRoot, sid, manifest.sha256['locald.exe']!);
}

/// Production owner bootstrap. Format3 identity is verified independently of
/// discovery; the discovery token grants no owner role on its own.
final class TrustedClientBootstrapEnvironment {
  TrustedClientBootstrapEnvironment._(this.bundle, this.localAppData, this.sid);
  final TrustedBuildBundle bundle;
  final String localAppData, sid;
  TrustedBuildManifest get manifest => bundle.manifest;
  String get localdPath => p.join(manifest.appRoot, 'locald.exe');

  static Future<TrustedClientBootstrapEnvironment> verify() async {
    try {
      final root = p.dirname(Platform.resolvedExecutable);
      final local = Platform.environment['LOCALAPPDATA'];
      if (local == null || !p.isAbsolute(local))
        throw StateError('PREREQUISITE_UNAVAILABLE');
      requireSafePath(local, local);
      final bundle = await verifyTrustedBuildBundle(root);
      final sid = currentUserSid();
      final identity = RetainedProcessIdentity.open(pid);
      try {
        verifyProcessImage(
          identity,
          sid,
          p.join(root, 'serverdeck.exe'),
          bundle.manifest.sha256['serverdeck.exe']!,
        );
      } finally {
        identity.close();
      }
      return TrustedClientBootstrapEnvironment._(bundle, local, sid);
    } on Object catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('PREREQUISITE_UNAVAILABLE');
    }
  }

  Future<DiscoveryDescriptor?> discovery() async {
    try {
      final directory = p.join(localAppData, 'ServerDeckNext', 'v1', 'runtime');
      final path = p.join(directory, 'default.discovery');
      requireSafePath(localAppData, path);
      if (queryLocalAttributes(directory) == null) return null;
      requireOwnerOnlyFileAcl(directory, sid);
      if (queryLocalAttributes(path) == null) return null;
      final bytes = await readProtectedFile(
        localAppData,
        path,
        sid,
        maxBytes: 16384,
      );
      return await DiscoveryCustody(
        DpapiProtection(),
        sid,
      ).unprotect(bytes, bundle.manifest.buildId);
    } on Object catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  OwnedLocaldChild launch() => _launchLocald(
    bundle.manifest.appRoot,
    sid,
    bundle.manifest.sha256['locald.exe']!,
  );
}

/// Same protected discovery and child lifecycle, with a separately verified MCP
/// executable. This class cannot issue an owner bootstrap identity.
final class TrustedMcpBootstrapEnvironment {
  TrustedMcpBootstrapEnvironment._(this.bundle, this.localAppData, this.sid);
  final TrustedBuildBundle bundle;
  final String localAppData, sid;

  static Future<TrustedMcpBootstrapEnvironment> verify(String appRoot) async {
    final local = Platform.environment['LOCALAPPDATA'];
    if (local == null || !p.isAbsolute(local))
      throw StateError('PREREQUISITE_UNAVAILABLE');
    requireSafePath(local, local);
    final bundle = await verifyTrustedBuildBundle(appRoot);
    final sid = currentUserSid();
    final identity = RetainedProcessIdentity.open(pid);
    try {
      verifyProcessImage(
        identity,
        sid,
        p.join(bundle.manifest.appRoot, 'mcp.exe'),
        bundle.manifest.sha256['mcp.exe']!,
      );
    } finally {
      identity.close();
    }
    return TrustedMcpBootstrapEnvironment._(bundle, local, sid);
  }

  Future<DiscoveryDescriptor?> discovery() =>
      TrustedClientBootstrapEnvironment._(
        bundle,
        localAppData,
        sid,
      ).discovery();
  OwnedLocaldChild launch() => _launchLocald(
    bundle.manifest.appRoot,
    sid,
    bundle.manifest.sha256['locald.exe']!,
    detached: true,
  );
}

OwnedLocaldChild _launchLocald(
  String appRoot,
  String sid,
  String imageHash, {
  bool detached = false,
}) {
  final localdPath = p.join(appRoot, 'locald.exe');
  requireSafePath(appRoot, localdPath);
  if (fileSha256(localdPath) != imageHash) throw StateError('INCOMPATIBLE');
  final exe = localdPath.toNativeUtf16();
  final command =
      '${quoteWindowsArgument(localdPath)} --workspace default --app-root ${quoteWindowsArgument(appRoot)}'
          .toNativeUtf16();
  final cwd = appRoot.toNativeUtf16();
  const allowed = {
    'SYSTEMROOT',
    'SYSTEMDRIVE',
    'WINDIR',
    'LOCALAPPDATA',
    'USERPROFILE',
    'APPDATA',
    'TEMP',
    'TMP',
  };
  final entries =
      Platform.environment.entries
          .where((e) => allowed.contains(e.key.toUpperCase()))
          .toList()
        ..sort((a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()));
  final environment =
      '${entries.map((e) => '${e.key}=${e.value}').join('\u0000')}\u0000\u0000'
          .toNativeUtf16();
  final startup = calloc<STARTUPINFO>(),
      process = calloc<PROCESS_INFORMATION>();
  var transferred = false;
  try {
    startup.ref.cb = sizeOf<STARTUPINFO>();
    if (!CreateProcess(
      PCWSTR(exe),
      PWSTR(command),
      null,
      null,
      false,
      // MCP hosts may kill their complete Job Object on EOF. A shared daemon
      // must never inherit that kill boundary. No unsafe fallback if the host
      // job refuses breakaway: an independently started locald is required.
      PROCESS_CREATION_FLAGS(detached ? 0x09000400 : 0x08000400),
      environment,
      PCWSTR(cwd),
      startup,
      process,
    ).value) {
      throw StateError(
        detached ? 'PREREQUISITE_UNAVAILABLE' : 'SERVICE_UNAVAILABLE',
      );
    }
    final identity = RetainedProcessIdentity.open(process.ref.dwProcessId);
    try {
      verifyProcessImage(identity, sid, localdPath, imageHash);
      final child = OwnedLocaldChild._(process.ref.hProcess.address);
      transferred = true;
      return child;
    } finally {
      identity.close();
    }
  } finally {
    if (!process.ref.hThread.isNull) CloseHandle(process.ref.hThread);
    if (!transferred && !process.ref.hProcess.isNull)
      CloseHandle(process.ref.hProcess);
    calloc.free(exe);
    calloc.free(command);
    calloc.free(cwd);
    calloc.free(environment);
    calloc.free(startup);
    calloc.free(process);
  }
}

/// Retained kernel handle; exit monitoring never trusts a reused PID.
/// The UI host serializes probing/close and transfers no externally supplied handle.
class OwnedLocaldChild {
  OwnedLocaldChild._(this._address);
  int _address;
  bool isLive() {
    if (_address == 0) throw StateError('SERVICE_UNAVAILABLE');
    final code = calloc<Uint32>();
    try {
      if (!GetExitCodeProcess(
        HANDLE(Pointer.fromAddress(_address)),
        code,
      ).value)
        throw StateError('SERVICE_UNAVAILABLE');
      return code.value == 259;
    } finally {
      calloc.free(code);
    }
  }

  void close() {
    if (_address == 0) return;
    if (!CloseHandle(HANDLE(Pointer.fromAddress(_address))).value)
      throw StateError('SERVICE_UNAVAILABLE');
    _address = 0;
  }
}

/// Windows CommandLineToArgv/CRT escaping, including trailing backslashes.
String quoteWindowsArgument(String value) {
  if (value.contains('\u0000')) throw ArgumentError('INVALID_ARGUMENT');
  return '"${value.replaceAllMapped(RegExp(r'(\\*)"'), (m) => '${m[1]}${m[1]}\\"').replaceAllMapped(RegExp(r'\\+$'), (m) => '${m[0]}${m[0]}')}"';
}
