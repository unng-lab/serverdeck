import 'dart:convert';
import 'dart:io';

/// Isolated reproduction of the debugger fixture's one-command stdin gate.
Future<void> main() async {
  stdout.writeln('WAITING_FOR_DEBUGGER');
  await stdout.flush();
  final command = await stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .single;
  if (command != 'start') throw StateError('INVALID_TEST_COMMAND');
  stdout.writeln('STDIN_GATE_COMPLETE');
  stdout.writeln('VERIFIER_MAIN_RETURNING');
}
