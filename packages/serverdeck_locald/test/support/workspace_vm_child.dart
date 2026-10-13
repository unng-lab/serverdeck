import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';

import 'state_store_child.dart' show check;

Future<void> main(List<String> arguments) async {
  final root = arguments[0], bundle = arguments[1], mode = arguments[2];
  final sid = currentUserSid();
  final digest = await Sha256().hash(utf8.encode('workspace-vm-crash-$root'));
  final name =
      'Global\\ServerDeckNext.v1.${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  final lease = await MutexLease.acquire(name, sid);
  check(lease.isHeld);
  final custody = KeyCustody(DpapiProtection(), sid);
  Workspace? workspace;
  try {
    if (mode == 'create' ||
        (arguments.length > 3 && arguments[3] == 'wait-debugger')) {
      stdout.writeln('WAITING_FOR_DEBUGGER');
      await stdout.flush();
      check(
        await stdin
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .single ==
            'start',
      );
      stdout.writeln('STDIN_GATE_COMPLETE');
      if (arguments.length > 3 && arguments[3] == 'trace-check') {
        try {
          throw StateError('TRACE_CHECK');
        } on StateError catch (error) {
          check(error.message == 'TRACE_CHECK');
        }
      }
    }
    try {
      workspace = await Workspace.open(
        localAppData: root,
        appRoot: bundle,
        lease: lease,
        custody: custody,
      );
    } on StateError catch (error) {
      if (mode != 'verify-blocked') {
        const safe = {
          'STORAGE_BLOCKED',
          'INCOMPATIBLE',
          'PREREQUISITE_UNAVAILABLE',
        };
        stderr.writeln(
          'INIT_FAILED_${safe.contains(error.message) ? error.message : 'UNKNOWN'}',
        );
      }
      check(mode == 'verify-blocked' && error.message == 'STORAGE_BLOCKED');
      stdout.writeln('PARTIAL_WORKSPACE_PRESERVED');
      return;
    }
    check(mode != 'verify-blocked');
    check(workspace.store.state.isInitialEmpty);
    stdout.writeln('OWNED_WORKSPACE_READY');
  } finally {
    stdout.writeln('WORKSPACE_CLOSE_BEGIN');
    await workspace?.close();
    stdout.writeln('WORKSPACE_CLOSE_END');
    stdout.writeln('MUTEX_CLOSE_BEGIN');
    await lease.close();
    stdout.writeln('MUTEX_CLOSE_END');
    stdout.writeln('VERIFIER_MAIN_RETURNING');
  }
}
