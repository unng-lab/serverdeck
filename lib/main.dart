import 'dart:io';

import 'package:flutter/material.dart';

import 'platform/desktop_application.dart';
import 'diagnostics/ui_runtime_diagnostics.dart';
import 'entry_mode.dart';
import 'platform/mcp_entry.dart';
import 'platform/mcp_stdio.dart';
export 'app.dart';

Future<void> main(List<String> arguments) async {
  final code = await dispatchServerDeck(
    arguments,
    application: () {
      installUiRuntimeDiagnostics();
      runApp(const DesktopApplication());
    },
    stdio: runDesktopMcp,
  );
  if (code != null) {
    try {
      await ChannelMcpStdioPort.finishOwned(code);
    } catch (_) {
      exit(1);
    }
  }
}
