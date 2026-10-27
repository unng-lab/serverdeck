import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Private test diagnostics only. Public qualification must discard the suffix.
final class OwnedFixtureFailure {
  OwnedFixtureFailure(
    this.primary,
    this.primaryStack,
    this.secondary,
    this.secondaryStack,
  );

  final Object primary;
  final StackTrace primaryStack;
  final Object secondary;
  final StackTrace secondaryStack;

  @override
  String toString() =>
      '$primary\nOWNED_FIXTURE_CLEANUP_FAILURE:\n$secondary\n$secondaryStack';
}

/// Await body and cleanup in the same lifetime, retaining the first failure.
Future<void> runOwnedFixtureLifecycle({
  required Future<void> Function() body,
  required Future<void> Function() cleanup,
  void Function(Object error, StackTrace stack)? onFirstFailure,
}) async {
  Object? primary;
  StackTrace? primaryStack;
  void observe(Object error, StackTrace stack) {
    try {
      onFirstFailure?.call(error, stack);
    } catch (_) {
      // Diagnostic refusal must not replace the fixture outcome.
    }
  }

  try {
    await body();
  } catch (error, stack) {
    primary = error;
    primaryStack = stack;
    observe(error, stack);
  }
  try {
    await cleanup();
  } catch (error, stack) {
    if (primary == null) {
      observe(error, stack);
      Error.throwWithStackTrace(error, stack);
    }
    Error.throwWithStackTrace(
      OwnedFixtureFailure(primary, primaryStack!, error, stack),
      primaryStack,
    );
  }
  if (primary != null) Error.throwWithStackTrace(primary, primaryStack!);
}

const trustedClientFailureBasename = 'trusted-client-server-failure';
const trustedClientFailurePhases = {
  'prepare',
  'bootstrap',
  'rpc-read',
  'rpc-write',
  'completion',
  'cleanup-child',
  'cleanup-worker',
};
const trustedClientFailureCodes = {
  'SERVICE_UNAVAILABLE',
  'UNSAFE_ENDPOINT',
  'IDENTITY_UNAVAILABLE',
  'TIMEOUT',
  'RESOURCE_LIMIT',
  'UNAUTHORIZED',
  'INCOMPATIBLE',
  'PREREQUISITE_UNAVAILABLE',
};

String? trustedClientSafeCode(Object error) {
  if (error is TimeoutException) return 'TIMEOUT';
  if (error is StateError &&
      trustedClientFailureCodes.contains(error.message)) {
    return error.message;
  }
  return null;
}

final class TrustedClientFailureRecord {
  TrustedClientFailureRecord._(this.phase, this.code);
  final String phase;
  final String? code;

  String get reasonMarker =>
      'TRUSTED_CLIENT_FIXTURE_FAILURE:$phase:${code ?? '-'}';
}

/// One attempted record per owned server, even when writing is refused.
final class TrustedClientFailureRecorder {
  TrustedClientFailureRecorder(this.root);
  final String root;
  bool _recorded = false;

  void record(String phase, Object error) {
    if (_recorded) return;
    _recorded = true;
    if (!trustedClientFailurePhases.contains(phase)) return;
    final bytes = ascii.encode(
      '1|$phase|${trustedClientSafeCode(error) ?? '-'}\n',
    );
    if (bytes.length > 128) return;
    try {
      File(p.join(root, trustedClientFailureBasename)).writeAsBytesSync(bytes);
    } catch (_) {
      // Best-effort private diagnostic; the original failure still propagates.
    }
  }
}

TrustedClientFailureRecord? readTrustedClientFailure(String root) {
  RandomAccessFile? handle;
  try {
    final file = File(p.join(root, trustedClientFailureBasename));
    handle = file.openSync();
    final before = handle.lengthSync();
    if (before > 128) return null;
    final bytes = handle.readSync(129);
    if (bytes.length != before ||
        handle.lengthSync() != before ||
        file.lengthSync() != before ||
        bytes.any((byte) => byte > 127)) {
      return null;
    }
    final match = RegExp(r'^1\|([a-z-]+)\|([A-Z_]+|-)\n$')
        .firstMatch(ascii.decode(bytes));
    if (match == null || match.end != bytes.length) return null;
    final phase = match[1]!, value = match[2]!;
    if (!trustedClientFailurePhases.contains(phase) ||
        (value != '-' && !trustedClientFailureCodes.contains(value))) {
      return null;
    }
    return TrustedClientFailureRecord._(phase, value == '-' ? null : value);
  } catch (_) {
    return null;
  } finally {
    try {
      handle?.closeSync();
    } catch (_) {
      // Unreadable diagnostics are absent, never a replacement fixture error.
    }
  }
}
