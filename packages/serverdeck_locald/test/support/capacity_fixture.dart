import 'dart:async';
import 'dart:convert';
import 'dart:io';

const capacityFixtureMaxCommits = 20000;
const capacityFixtureYieldEvery = 16;
const capacityFixturePhaseFileName = 'trust-capacity-fixture-phase';
const capacityFixtureUnknownPhase = 'unknown';
const capacityFixturePhaseTokens = <String>{
  'capacity-start',
  'capacity-reader-ready',
  'capacity-prefill-0',
  'capacity-prefill-1000',
  'capacity-prefill-2000',
  'capacity-prefill-3000',
  'capacity-prefill-4000',
  'capacity-prefill-5000',
  'capacity-prefill-6000',
  'capacity-prefill-7000',
  'capacity-prefill-8000',
  'capacity-prefill-9000',
  'capacity-prefill-10000',
  'capacity-prefill-11000',
  'capacity-prefill-12000',
  'capacity-prefill-13000',
  'capacity-prefill-14000',
  'capacity-prefill-15000',
  'capacity-prefill-16000',
  'capacity-prefill-17000',
  'capacity-prefill-18000',
  'capacity-prefill-19000',
  'capacity-prefill-20000',
  'capacity-full',
  'capacity-confirm-refused',
  'capacity-reader-released',
  'capacity-recovery-confirm',
  'capacity-recovered',
  'capacity-replay-verified',
  'capacity-revoke-verified',
  'capacity-complete',
};

/// Every callback completes one independent durable maintenance transaction.
/// A zero-delay timer gives the event queue a turn after each 16 commits.
Future<bool> prefillCapacityFixture({
  required void Function() commitSync,
  required bool Function(Object) isCapacityFailure,
  void Function(int)? onBucket,
}) async {
  void observe(int completed) {
    try {
      onBucket?.call(completed);
    } catch (_) {
      // Diagnostic observers cannot change the fixture outcome.
    }
  }

  observe(0);
  for (var completed = 0; completed < capacityFixtureMaxCommits;) {
    try {
      commitSync();
    } catch (error) {
      if (!isCapacityFailure(error)) rethrow;
      return true;
    }
    completed++;
    if (completed % 1000 == 0) observe(completed);
    if (completed % capacityFixtureYieldEvery == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return false;
}

File _phaseFile(String root) =>
    File('$root${Platform.pathSeparator}$capacityFixturePhaseFileName');

/// Only fixed tokens are written, and observer failures never mask the actor.
void writeCapacityFixturePhase(String root, String phase) {
  final checked = capacityFixturePhaseTokens.contains(phase)
      ? phase
      : capacityFixtureUnknownPhase;
  try {
    _phaseFile(root)
        .writeAsStringSync('$checked\n', encoding: ascii, flush: true);
  } catch (_) {
    // The parent treats missing or incomplete observations as unknown.
  }
}

/// Read at most 65 bytes so an oversized observation always fails closed.
String readCapacityFixturePhase(String root) {
  try {
    final input = _phaseFile(root).openSync();
    try {
      if (input.lengthSync() > 64) return capacityFixtureUnknownPhase;
      final bytes = input.readSync(65);
      if (bytes.isEmpty || bytes.length > 64 || input.lengthSync() > 64) {
        return capacityFixtureUnknownPhase;
      }
      final value = ascii.decode(bytes, allowInvalid: false);
      if (!value.endsWith('\n')) return capacityFixtureUnknownPhase;
      final phase = value.substring(0, value.length - 1);
      return capacityFixturePhaseTokens.contains(phase)
          ? phase
          : capacityFixtureUnknownPhase;
    } finally {
      input.closeSync();
    }
  } catch (_) {
    return capacityFixtureUnknownPhase;
  }
}
