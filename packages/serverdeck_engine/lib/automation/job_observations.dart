import 'dart:convert';

import 'package:serverdeck_protocol/automation/job_observation.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor.dart';
import 'package:serverdeck_protocol/executor_jobs.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../platform/ports.dart' show EngineClock;

const _terminal = {
  'succeeded',
  'failed',
  'cancelled',
  'cancelled-partial',
  'unknown',
};
const _progressFields = {
  'attemptId',
  'state',
  'sequence',
  'stepIndex',
  'authorizationEpoch',
  'failureCode',
  'checks',
};
Never _bad() => throw StateError('RUNTIME_INCOMPATIBLE');
void _integer(Object? value, int maximum) {
  if (value is! int || value < 0 || value > maximum) _bad();
}

String _target(Map<String, Object?> value) {
  requireFields(value, {
    'workspaceId',
    'serverId',
    'targetRevision',
    'connectionRevision',
    'accessRevision',
    'trustRevision',
  });
  requireUuid(value['workspaceId']);
  requireUuid(value['serverId']);
  for (final field in [
    'targetRevision',
    'connectionRevision',
    'accessRevision',
    'trustRevision',
  ]) {
    requireRevision(value[field]);
  }
  return utf8.decode(StrictCodec().canonical(value));
}

/// Captured actual-session identity data. Structural equality grants no access.
final class JobObserverIdentity {
  JobObserverIdentity({
    required this.jobId,
    required this.attemptId,
    required this.hostId,
    required this.registryDigest,
    required Map<String, Object?> target,
  }) : targetJson = _target(target),
       serverId = requireUuid(target['serverId']),
       workspaceId = requireUuid(target['workspaceId']) {
    requireUuid(jobId);
    requireUuid(attemptId);
    requireUuid(hostId);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(registryDigest)) _bad();
  }
  final String jobId,
      attemptId,
      hostId,
      registryDigest,
      serverId,
      workspaceId,
      targetJson;
  bool sameAs(JobObserverIdentity other) =>
      jobId == other.jobId &&
      attemptId == other.attemptId &&
      hostId == other.hostId &&
      registryDigest == other.registryDigest &&
      targetJson == other.targetJson;
}

/// Only bounded comparison facts, never challenges, events, free text or keys.
/// Capture validates data, not the enrolled session or permission to publish.
final class JobObservationProgress {
  JobObservationProgress._(this._json);
  factory JobObservationProgress.fromStatus(ExecutorJobStatus status) {
    final value = status.toJson();
    return JobObservationProgress.capture({
      for (final key in _progressFields) key: value[key],
    });
  }
  factory JobObservationProgress.capture(Map<String, Object?> value) {
    final copy = StrictCodec().decode(
      StrictCodec().encode(value, maxBytes: 8192),
      maxBytes: 8192,
    );
    requireFields(copy, _progressFields);
    requireUuid(copy['attemptId']);
    if (!executorJobStates.contains(copy['state']) ||
        copy['failureCode'] != null &&
            !executorCodes.contains(copy['failureCode']))
      _bad();
    _integer(copy['sequence'], 9223372036854775807);
    _integer(copy['stepIndex'], 32);
    _integer(copy['authorizationEpoch'], 2147483647);
    final checks = copy['checks'];
    if (checks is! List || checks.length > 32) _bad();
    final ids = <String>{};
    for (final raw in checks) {
      if (raw is! Map<String, Object?>) _bad();
      requireFields(raw, {'checkId', 'passed'});
      if (raw['checkId'] is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{0,31}$')
              .hasMatch(raw['checkId'] as String) ||
          !ids.add(raw['checkId'] as String) ||
          raw['passed'] is! bool)
        _bad();
    }
    checks.sort(
      (a, b) => ((a as Map)['checkId'] as String).compareTo(
        (b as Map)['checkId'] as String,
      ),
    );
    return JobObservationProgress._(utf8.decode(StrictCodec().canonical(copy)));
  }
  final String _json;
  Map<String, Object?> get _value => jsonDecode(_json) as Map<String, Object?>;
  String get attemptId => _value['attemptId'] as String;
  int get sequence => _value['sequence'] as int;
  int get step => _value['stepIndex'] as int;
  int get epoch => _value['authorizationEpoch'] as int;
  bool get terminal => _terminal.contains(_value['state']);
}

/// Private callback correlation only; it cannot authorize store/root work.
final class JobObserverBinding {
  JobObserverBinding._(this._owner, this._entry, this.identity);
  final LocalJobObservations _owner;
  final _Entry _entry;
  final JobObserverIdentity identity;
}

final class _Entry {
  _Entry(this.attemptId);
  final String attemptId;
  JobObserverBinding? binding;
  JobObserverIdentity? sampleIdentity;
  JobObservationProgress? progress;
  Duration? received;
  DateTime? observed;
  int floor = 0;
  bool invalidated = false, seenInBinding = false;
}

/// Bounded engine-local samples. No I/O, timers, mutations, permissions or locks.
final class LocalJobObservations {
  LocalJobObservations({
    required this.generation,
    required this.workspaceId,
    required this.clock,
  }) {
    requireUuid(generation);
    requireUuid(workspaceId);
  }
  static const capacity = 1250, freshness = Duration(seconds: 5);
  final String generation, workspaceId;
  final EngineClock clock;
  final _entries = <String, _Entry>{};
  bool _closed = false;
  int get count => _entries.length;

  _Entry _entry(String jobId, String attemptId) {
    requireUuid(jobId);
    requireUuid(attemptId);
    final prior = _entries[jobId];
    if (prior != null) {
      if (prior.attemptId != attemptId) _bad();
      return prior;
    }
    if (_entries.length >= capacity) throw StateError('RESOURCE_LIMIT');
    return _entries[jobId] = _Entry(attemptId);
  }

  JobObserverBinding begin(JobObserverIdentity identity) {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (identity.workspaceId != workspaceId) _bad();
    final entry = _entry(identity.jobId, identity.attemptId);
    if (entry.sampleIdentity case final JobObserverIdentity previous) {
      if (previous.hostId != identity.hostId) _bad();
    }
    final binding = JobObserverBinding._(this, entry, identity);
    entry.binding = binding;
    entry.seenInBinding = false;
    entry.invalidated = false;
    return binding;
  }

  bool _current(JobObserverBinding binding) =>
      !_closed &&
      identical(binding._owner, this) &&
      identical(_entries[binding.identity.jobId], binding._entry) &&
      identical(binding._entry.binding, binding);

  bool advanceFloor(JobObserverBinding binding, int sequence) {
    _integer(sequence, 9223372036854775807);
    if (!_current(binding)) return false;
    if (sequence > binding._entry.floor) binding._entry.floor = sequence;
    return true;
  }

  bool observe(
    JobObserverBinding binding,
    JobObservationProgress progress, {
    required Map<String, Object?>? currentTarget,
  }) {
    if (!_current(binding)) return false;
    final entry = binding._entry;
    if (currentTarget == null ||
        _target(currentTarget) != binding.identity.targetJson) {
      entry.invalidated = true;
      entry.binding = null;
      return false;
    }
    if (progress.attemptId != binding.identity.attemptId ||
        progress.sequence < entry.floor)
      _bad();
    final previous = entry.progress;
    if (previous != null &&
        (progress.step < previous.step ||
            progress.epoch < previous.epoch ||
            progress.sequence == previous.sequence &&
                progress._json != previous._json))
      _bad();
    final received = clock.elapsed;
    final observed = DateTime.fromMillisecondsSinceEpoch(
      clock.utcNow.toUtc().millisecondsSinceEpoch,
      isUtc: true,
    );
    entry.floor = progress.sequence;
    entry.progress = progress;
    entry.sampleIdentity = binding.identity;
    entry.received = received;
    entry.observed = observed;
    entry.seenInBinding = true;
    if (progress.terminal) entry.binding = null;
    return true;
  }

  void detach(JobObserverBinding binding) {
    if (_current(binding)) binding._entry.binding = null;
  }

  void detachServer(String server) {
    for (final entry in _entries.values) {
      if (entry.binding?.identity.serverId == server) entry.binding = null;
    }
  }

  void invalidateServer(String server) {
    for (final entry in _entries.values) {
      if (entry.binding?.identity.serverId == server ||
          entry.sampleIdentity?.serverId == server) {
        entry.invalidated = true;
        entry.binding = null;
      }
    }
  }

  void prune(Set<String> retainedJobIds) {
    _entries.removeWhere((id, entry) {
      if (retainedJobIds.contains(id)) return false;
      entry.binding = null;
      return true;
    });
  }

  void close() {
    _closed = true;
    for (final entry in _entries.values) entry.binding = null;
  }

  LocalJobObservationView snapshot({
    required String jobId,
    required String attemptId,
    required Map<String, Object?>? currentTarget,
  }) {
    final entry = _entry(jobId, attemptId), sample = entry.sampleIdentity;
    var state = JobObservationState.detached;
    if (sample != null) {
      final bindingIdentity = entry.binding?.identity;
      if (entry.invalidated ||
          currentTarget == null ||
          _target(currentTarget) != sample.targetJson ||
          bindingIdentity != null && !bindingIdentity.sameAs(sample)) {
        state = JobObservationState.stale;
      } else if (entry.binding != null && entry.seenInBinding) {
        final age = clock.elapsed - entry.received!;
        state = age >= Duration.zero && age < freshness
            ? JobObservationState.attached
            : JobObservationState.stale;
      }
    }
    return LocalJobObservationView.fromJson({
      'generation': generation,
      'attemptId': attemptId,
      'state': state.name,
      'lastSequence': entry.progress?.sequence,
      'observedAt': entry.observed?.toIso8601String(),
    });
  }
}
