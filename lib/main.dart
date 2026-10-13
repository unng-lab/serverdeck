import 'package:flutter/material.dart';

import 'app.dart';
import 'diagnostics/ui_runtime_diagnostics.dart';
export 'app.dart';

void main() {
  installUiRuntimeDiagnostics();
  runApp(const FoundationApp());
}
