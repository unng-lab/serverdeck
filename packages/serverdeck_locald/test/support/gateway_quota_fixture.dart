import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../serverdeck_windows/test/support/trusted_client_fixture.dart';

enum GatewayQuotaFailureRole { server, bridge }

const gatewayQuotaServerPhases = {
  'scenario-prepare',
  'server-prepare',
  'server-bootstrap',
  'server-admitted16',
  'server-quota-oracle',
  'server-cancelled16',
  'server-cancel-oracle',
  'server-child-exit',
  'server-stderr',
  'server-serving',
  'server-cleanup',
  'scenario-cleanup',
};
const gatewayQuotaBridgePhases = {
  'bridge-bootstrap',
  'bridge-admission',
  'bridge-cancellation',
  'bridge-completion',
  'bridge-cleanup',
};
const gatewayQuotaFailureCodes = {
  'SERVICE_UNAVAILABLE',
  'UNSAFE_ENDPOINT',
  'IDENTITY_UNAVAILABLE',
  'TIMEOUT',
  'RESOURCE_LIMIT',
  'UNAUTHORIZED',
  'INCOMPATIBLE',
  'PREREQUISITE_UNAVAILABLE',
  'FORBIDDEN',
  'FIXTURE_ASSERTION',
};

String gatewayQuotaFailureBasename(GatewayQuotaFailureRole role) =>
    'gateway-quota-${role.name}-failure';

final class GatewayQuotaFailureRecord {
  GatewayQuotaFailureRecord._(this.phase, this.code);
  final String phase;
  final String? code;

  String get reasonMarker =>
      'GATEWAY_QUOTA_FIXTURE_FAILURE:$phase:${code ?? '-'}';
}

/// A validated bridge record carried only by an observed failing boundary.
final class GatewayQuotaBridgeFailure {
  GatewayQuotaBridgeFailure._(
    this.record,
    this.boundaryError,
    this.boundaryStack,
  );
  final GatewayQuotaFailureRecord record;
  final Object boundaryError;
  final StackTrace boundaryStack;

  @override
  String toString() => '$boundaryError\n$boundaryStack';
}

Object _primary(Object error) {
  while (error is OwnedFixtureFailure) {
    error = error.primary;
  }
  return error;
}

/// One attempted write, including invalid phases and failed diagnostics.
final class GatewayQuotaFailureRecorder {
  GatewayQuotaFailureRecorder(this.root, this.role, {this.gatewayCodeOf});
  final String root;
  final GatewayQuotaFailureRole role;
  final String? Function(Object error)? gatewayCodeOf;
  bool _attempted = false;

  void record(String phase, Object error) {
    if (_attempted) return;
    _attempted = true;
    error = _primary(error);
    String? code;
    if (role == GatewayQuotaFailureRole.server &&
        error is GatewayQuotaBridgeFailure) {
      phase = error.record.phase;
      code = error.record.code;
    } else {
      final phases = role == GatewayQuotaFailureRole.bridge
          ? gatewayQuotaBridgePhases
          : gatewayQuotaServerPhases;
      if (!phases.contains(phase)) return;
      if (error is TimeoutException) {
        code = 'TIMEOUT';
      } else if (error is StateError) {
        if (gatewayQuotaFailureCodes.contains(error.message)) {
          code = error.message;
        }
      } else {
        try {
          code = gatewayCodeOf?.call(error);
        } catch (_) {
          // An observer cannot replace the original outcome.
        }
      }
    }
    if (!gatewayQuotaFailureCodes.contains(code)) code = null;
    final bytes = ascii.encode('1|$phase|${code ?? '-'}\n');
    if (bytes.length > 128) return;
    try {
      File.fromUri(
        Directory(root).uri.resolve(gatewayQuotaFailureBasename(role)),
      ).writeAsBytesSync(bytes);
    } catch (_) {
      // Best-effort diagnostics; never retry or change the fixture outcome.
    }
  }
}

GatewayQuotaFailureRecord? readGatewayQuotaFailure(
  String root,
  GatewayQuotaFailureRole role,
) {
  RandomAccessFile? handle;
  try {
    final file = File.fromUri(
      Directory(root).uri.resolve(gatewayQuotaFailureBasename(role)),
    );
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
    final match = RegExp(r'^1\|([a-z-]+[0-9]*)\|([A-Z_]+|-)\n$')
        .firstMatch(ascii.decode(bytes));
    if (match == null || match.end != bytes.length) return null;
    final phase = match[1]!, code = match[2]!;
    final phases = role == GatewayQuotaFailureRole.bridge
        ? gatewayQuotaBridgePhases
        : {...gatewayQuotaServerPhases, ...gatewayQuotaBridgePhases};
    if (!phases.contains(phase) ||
        (code != '-' && !gatewayQuotaFailureCodes.contains(code))) {
      return null;
    }
    return GatewayQuotaFailureRecord._(phase, code == '-' ? null : code);
  } catch (_) {
    return null;
  } finally {
    try {
      handle?.closeSync();
    } catch (_) {
      // An unreadable diagnostic is absent.
    }
  }
}

/// Runs the original assertion without waiting for additional bridge evidence.
void checkGatewayQuotaBridgeBoundary(
  String root, {
  required bool causal,
  required void Function() check,
}) {
  try {
    check();
  } catch (error, stack) {
    final record = causal
        ? readGatewayQuotaFailure(root, GatewayQuotaFailureRole.bridge)
        : null;
    if (record != null) {
      Error.throwWithStackTrace(
        GatewayQuotaBridgeFailure._(record, error, stack),
        stack,
      );
    }
    rethrow;
  }
}

final class GatewayQuotaLifecycle {
  GatewayQuotaLifecycle(this.recorder, this.phase);
  final GatewayQuotaFailureRecorder recorder;
  String phase;

  void observe(Object error, StackTrace stack) => recorder.record(phase, error);

  Future<void> run({
    required Future<void> Function() body,
    required Future<void> Function() cleanup,
    required String cleanupPhase,
  }) => runOwnedFixtureLifecycle(
    body: body,
    cleanup: () async {
      phase = cleanupPhase;
      await cleanup();
    },
    onFirstFailure: observe,
  );
}

String formatGatewayQuotaFailure(Object error, StackTrace stack) {
  final secondary = <String>[];
  while (error is OwnedFixtureFailure) {
    secondary.insert(0, '${error.secondary}\n${error.secondaryStack}');
    stack = error.primaryStack;
    error = error.primary;
  }
  while (error is GatewayQuotaBridgeFailure) {
    stack = error.boundaryStack;
    error = error.boundaryError;
  }
  final primary = '$error\n${stack.toString().split('\n').take(8).join('\n')}';
  return secondary.isEmpty
      ? primary
      : '$primary\nGATEWAY_QUOTA_SECONDARY_FAILURE:\n${secondary.join('\n')}';
}

String gatewayQuotaReasonPrefix(String root) {
  final record = readGatewayQuotaFailure(root, GatewayQuotaFailureRole.server);
  return '${record == null ? '' : '${record.reasonMarker}\n'}'
      'GATEWAY_QUOTA_PRIVATE_OUTPUT:\n';
}
