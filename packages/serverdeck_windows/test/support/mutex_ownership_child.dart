import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/security.dart';

Future<void> main(List<String> arguments) async {
  final name = arguments[0], mode = arguments[1], sid = currentUserSid();
  if (mode == 'hold') {
    final lease = await MutexLease.acquire(name, sid);
    if (!lease.isHeld) throw StateError('EXPECTED_OWNER');
    try {
      stdout.writeln('MUTEX_HELD');
      await stdout.flush();
      await stdin.drain<void>();
    } finally {
      await lease.close();
    }
    return;
  }
  var falseOwners = 0, closeFailures = 0;
  for (var index = 0; index < 1000; index++) {
    final lease = await MutexLease.acquire(name, sid);
    if (lease.isHeld) falseOwners++;
    try {
      await lease.close();
    } on StateError {
      closeFailures++;
    }
  }
  stdout.writeln(jsonEncode([falseOwners, closeFailures]));
}
