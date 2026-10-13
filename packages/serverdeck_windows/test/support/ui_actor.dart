import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

/// Acceptance-only launcher. Its retained handle can affect only its own child.
class UiActor {
  UiActor._(this._handle, this.pid);
  int _handle;
  final int pid;

  /// Requests the same native close as the title-bar button, only for this PID.
  static void closeCurrentWindow() {
    final window = _currentWindow();
    if (!PostMessage(window, WM_CLOSE, WPARAM(0), LPARAM(0)).value) {
      throw StateError('ACTOR_WINDOW_CLOSE_FAILED');
    }
  }

  /// Keep both test windows partly visible: occluded Windows views stop frames.
  static void positionObserverWindow({bool witness = false}) {
    if (!SetWindowPos(
      _currentWindow(),
      null,
      witness ? 200 : 100,
      witness ? 160 : 80,
      1100,
      700,
      SET_WINDOW_POS_FLAGS(SWP_NOZORDER | SWP_NOACTIVATE),
    ).value) {
      throw StateError('ACTOR_WINDOW_POSITION_FAILED');
    }
  }

  static HWND _currentWindow() {
    final windowClass = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
    final processId = calloc<Uint32>();
    HWND? after;
    try {
      for (var count = 0; count < 1024; count++) {
        final window = FindWindowEx(
          null,
          after,
          PCWSTR(windowClass),
          null,
        ).value;
        if (window.isNull) break;
        GetWindowThreadProcessId(window, processId);
        if (processId.value == GetCurrentProcessId()) {
          return window;
        }
        after = window;
      }
      throw StateError('ACTOR_WINDOW_MISSING');
    } finally {
      calloc.free(windowClass);
      calloc.free(processId);
    }
  }

  static Future<UiActor> launchConcurrentObserver() => launch(concurrent: true);
  static Future<UiActor> launchWitness() =>
      launch(role: 'witness', concurrent: true);
  static Future<UiActor> launchCrashObserver() => launch(crash: true);
  static Future<UiActor> launchRecovered() =>
      launch(role: 'recovered', crash: true);
  static Future<UiActor> launchPendingObserver() => launch(pending: true);
  static Future<UiActor> launchServiceOwner() => launch(serviceOwner: true);
  static Future<UiActor> launchOwnerRecoveryObserver() =>
      launch(ownerRecovery: true);

  static Future<UiActor> launch({
    String role = 'observer',
    bool concurrent = false,
    bool crash = false,
    bool pending = false,
    bool serviceOwner = false,
    bool ownerRecovery = false,
  }) async {
    if ((role != 'observer' && role != 'witness' && role != 'recovered') ||
        [
              crash,
              concurrent,
              pending,
              serviceOwner,
              ownerRecovery,
            ].where((value) => value).length >
            1 ||
        ((pending || serviceOwner || ownerRecovery) && role != 'observer')) {
      throw StateError('ACTOR_ROLE_INVALID');
    }
    final environment = await ClientBootstrapEnvironment.verify();
    final executable = serviceOwner
        ? environment.localdPath
        : Platform.resolvedExecutable;
    final exe = executable.toNativeUtf16();
    final command =
        (serviceOwner
                ? '${quoteWindowsArgument(executable)} --workspace default --app-root ${quoteWindowsArgument(environment.manifest.appRoot)}'
                : quoteWindowsArgument(executable))
            .toNativeUtf16();
    final cwd = environment.manifest.appRoot.toNativeUtf16();
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
            .where((entry) => allowed.contains(entry.key.toUpperCase()))
            .toList()
          ..addAll(
            serviceOwner
                ? <MapEntry<String, String>>[]
                : [
                    MapEntry('SERVERDECK_UI_ROLE', role),
                    MapEntry(
                      'SERVERDECK_UI_SCENARIO',
                      ownerRecovery
                          ? 'owner-recovery'
                          : pending
                          ? 'unknown-inflight'
                          : crash
                          ? 'crash-observer'
                          : concurrent
                          ? 'concurrent-three'
                          : 'two-window',
                    ),
                  ],
          )
          ..sort((a, b) => a.key.toUpperCase().compareTo(b.key.toUpperCase()));
    final block =
        '${entries.map((entry) => '${entry.key}=${entry.value}').join('\u0000')}\u0000\u0000'
            .toNativeUtf16();
    final startup = calloc<STARTUPINFO>(),
        information = calloc<PROCESS_INFORMATION>();
    var transferred = false;
    try {
      startup.ref.cb = sizeOf<STARTUPINFO>();
      startup.ref.dwFlags = STARTF_USESHOWWINDOW;
      startup.ref.wShowWindow = SW_HIDE;
      if (!CreateProcess(
        PCWSTR(exe),
        PWSTR(command),
        null,
        null,
        false,
        PROCESS_CREATION_FLAGS(0x08000400),
        block,
        PCWSTR(cwd),
        startup,
        information,
      ).value)
        throw StateError('ACTOR_LAUNCH_FAILED');
      final identity = RetainedProcessIdentity.open(
        information.ref.dwProcessId,
      );
      try {
        verifyProcessImage(
          identity,
          environment.sid,
          executable,
          environment.manifest.sha256[serviceOwner
              ? 'locald.exe'
              : 'serverdeck.exe']!,
        );
        transferred = true;
        return UiActor._(
          information.ref.hProcess.address,
          information.ref.dwProcessId,
        );
      } finally {
        identity.close();
      }
    } finally {
      if (!information.ref.hThread.isNull) CloseHandle(information.ref.hThread);
      if (!transferred && !information.ref.hProcess.isNull) {
        // This handle comes only from our own verified-image CreateProcess.
        TerminateProcess(information.ref.hProcess, 73);
        CloseHandle(information.ref.hProcess);
      }
      calloc.free(exe);
      calloc.free(command);
      calloc.free(cwd);
      calloc.free(block);
      calloc.free(startup);
      calloc.free(information);
    }
  }

  int get exitCode {
    if (_handle == 0) throw StateError('ACTOR_HANDLE_CLOSED');
    final code = calloc<Uint32>();
    try {
      if (!GetExitCodeProcess(HANDLE(Pointer.fromAddress(_handle)), code).value)
        throw StateError('ACTOR_QUERY_FAILED');
      return code.value;
    } finally {
      calloc.free(code);
    }
  }

  void terminateIfLive() {
    if (_handle != 0 &&
        exitCode == 259 &&
        !TerminateProcess(HANDLE(Pointer.fromAddress(_handle)), 73).value)
      throw StateError('ACTOR_STOP_FAILED');
  }

  void close() {
    if (_handle == 0) return;
    if (!CloseHandle(HANDLE(Pointer.fromAddress(_handle))).value)
      throw StateError('ACTOR_CLOSE_FAILED');
    _handle = 0;
  }
}
