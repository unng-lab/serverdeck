import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:serverdeck_windows/paths.dart';

import '../lib/main.dart' as app;
import '../lib/shell/readiness_view.dart';
import 'support/runtime_hooks.dart';
import 'support/foreign_access_proof.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final local = Platform.environment['LOCALAPPDATA'] ?? '';
  final owner = Platform.environment['SERVERDECK_ACCEPTANCE_OWNER_SID'] ?? '';
  final role = Platform.environment['SERVERDECK_ACCEPTANCE_USER_ROLE'] ?? '';
  if (!RegExp(
        r'[\\/]\.local[\\/]environment-acceptance-[a-f0-9]{32}[\\/]profile$',
      ).hasMatch(local) ||
      !RegExp(r'^S-1-(?:\d+-){1,14}\d+$').hasMatch(owner) ||
      !{'owner', 'foreign'}.contains(role)) {
    throw StateError('OWNED_USER_ACCEPTANCE_REQUIRED');
  }
  final sid = currentUserSid();
  if ((role == 'owner') != (sid == owner)) {
    throw StateError('ACTUAL_OS_USER_REQUIRED');
  }
  // No test signals are created in the owner's private profile by this target.
  testWidgetsWithRuntimeHooks('actual OS user boundary role=$role', (
    tester,
  ) async {
    Object? ownerProfilePathFailure;
    if (role == 'foreign') {
      // Read-only production check, on the exact checkpoint-bound profile.
      // Preserve only its native failure classification, never profile bytes.
      try {
        requireSafePath(local, local);
      } on Object catch (error) {
        ownerProfilePathFailure = error;
      }
    }
    app.main();
    bool reached() => role == 'owner'
        ? find.text('Environment checkpoint').evaluate().isNotEmpty
        : find.byType(ReadinessView).evaluate().any((element) {
            final view = element.widget as ReadinessView;
            return foreignAccessRefusalProved(
              view.state,
              view.reason,
              ownerProfilePathFailure: ownerProfilePathFailure,
            );
          });
    final watch = Stopwatch()..start();
    while (!reached() && watch.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(reached(), true);
    if (role == 'foreign') {
      expect(find.text('Environment checkpoint'), findsNothing);
      expect(find.text('Создать профиль'), findsNothing);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    // Allow normal owner disconnect/shutdown; no process kill or reset.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(seconds: 6)),
    );
    // ignore: avoid_print
    print(
      role == 'owner'
          ? 'COMPILED_OWNER_USER_BASELINE_PROVED'
          : 'COMPILED_ACTUAL_FOREIGN_USER_ACCESS_REFUSAL_PROVED',
    );
  });
}
