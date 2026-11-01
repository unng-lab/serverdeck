import 'package:serverdeck_engine/automation/job_observations.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_protocol/automation/job_observation.dart';
import 'package:test/test.dart';

import '../storage/actual_state_store_test.dart' show id, failure;
import '../support/schema3_fixture.dart' as fixture;

final class Clock implements EngineClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime utcNow = DateTime.utc(2026, 10, 31, 10);
}

Map<String, Object?> target([int revision = 1]) => {
  'workspaceId': fixture.workspace,
  'serverId': fixture.profile,
  'targetRevision': revision.toString(),
  'connectionRevision': '1',
  'accessRevision': '1',
  'trustRevision': '1',
};
JobObserverIdentity identity({
  int revision = 1,
  String? job,
  String? attempt,
  String? host,
}) => JobObserverIdentity(
  jobId: job ?? id(1),
  attemptId: attempt ?? id(2),
  hostId: host ?? id(3),
  registryDigest: 'a' * 64,
  target: target(revision),
);
JobObservationProgress progress(
  int sequence, {
  int step = 0,
  int epoch = 0,
  String state = 'running',
  List<Map<String, Object?>> checks = const [],
}) => JobObservationProgress.capture({
  'attemptId': id(2),
  'state': state,
  'sequence': sequence,
  'stepIndex': step,
  'authorizationEpoch': epoch,
  'failureCode': null,
  'checks': checks,
});
LocalJobObservationView snapshot(LocalJobObservations s, [int revision = 1]) =>
    s.snapshot(jobId: id(1), attemptId: id(2), currentTarget: target(revision));
LocalJobObservations store(Clock clock, {String? generation}) =>
    LocalJobObservations(
      generation: generation ?? id(4),
      workspaceId: fixture.workspace,
      clock: clock,
    );

void main() {
  test('target counters retain existing decimal-string int64 precision and reject an int substitute', () {
    final current = {...target(), 'targetRevision': '9223372036854775807'};
    final s = store(Clock());
    final binding = s.begin(
      JobObserverIdentity(
        jobId: id(1),
        attemptId: id(2),
        hostId: id(3),
        registryDigest: 'a' * 64,
        target: current,
      ),
    );
    expect(s.observe(binding, progress(1), currentTarget: current), isTrue);
    expect(
      s.snapshot(jobId: id(1), attemptId: id(2), currentTarget: current).state,
      JobObservationState.attached,
    );
    expect(
      () => JobObserverIdentity(
        jobId: id(8),
        attemptId: id(9),
        hostId: id(3),
        registryDigest: 'a' * 64,
        target: {...target(), 'targetRevision': 1},
      ),
      throwsFormatException,
    );
  });

  test('opening has no sample and strict5s freshness uses monotonic rather than UTC time', () {
    final clock = Clock(), s = store(clock), binding = s.begin(identity());
    expect(snapshot(s).state, JobObservationState.detached);
    expect(snapshot(s).lastSequence, isNull);
    expect(s.observe(binding, progress(1), currentTarget: target()), isTrue);
    final observed = snapshot(s).observedAt;
    clock.utcNow = DateTime.utc(2040);
    clock.elapsed =
        const Duration(seconds: 5) - const Duration(microseconds: 1);
    expect(snapshot(s).state, JobObservationState.attached);
    expect(snapshot(s).observedAt, observed);
    clock.elapsed = const Duration(seconds: 5);
    expect(snapshot(s).state, JobObservationState.stale);
    s.detach(binding);
    expect(snapshot(s).state, JobObservationState.detached);
    expect(snapshot(s).lastSequence, 1);
  });
  test('replacement retains order and old callback or detach cannot change a new sample', () {
    final s = store(Clock()), first = s.begin(identity());
    s.observe(first, progress(3), currentTarget: target());
    final next = s.begin(identity());
    expect(snapshot(s).state, JobObservationState.detached);
    expect(s.observe(first, progress(9), currentTarget: target()), isFalse);
    s.detach(first);
    expect(
      () => s.observe(next, progress(2), currentTarget: target()),
      failure('RUNTIME_INCOMPATIBLE'),
    );
    expect(
      () => s.observe(
        next,
        progress(3, state: 'queued'),
        currentTarget: target(),
      ),
      failure('RUNTIME_INCOMPATIBLE'),
    );
    expect(s.observe(next, progress(4), currentTarget: target()), isTrue);
    s.detach(first);
    expect(snapshot(s).state, JobObservationState.attached);
    expect(snapshot(s).lastSequence, 4);
  });
  test('target and enrollment invalidation remain stale until a new verified sample', () {
    final s = store(Clock()), first = s.begin(identity());
    s.observe(first, progress(1), currentTarget: target());
    expect(snapshot(s, 2).state, JobObservationState.stale);
    expect(s.observe(first, progress(2), currentTarget: target(2)), isFalse);
    final next = s.begin(identity(revision: 2));
    expect(snapshot(s, 2).state, JobObservationState.stale);
    s.observe(next, progress(2), currentTarget: target(2));
    expect(snapshot(s, 2).state, JobObservationState.attached);
    s.invalidateServer(fixture.profile);
    expect(snapshot(s, 2).state, JobObservationState.stale);
    expect(s.observe(next, progress(3), currentTarget: target(2)), isFalse);
  });
  test('foreign instance/generation/workspace and changed host cannot reuse correlation', () {
    final first = store(Clock()), binding = first.begin(identity());
    first.observe(binding, progress(1), currentTarget: target());
    final next = store(Clock(), generation: id(5));
    expect(
      next.observe(binding, progress(2), currentTarget: target()),
      isFalse,
    );
    expect(snapshot(next).lastSequence, isNull);
    expect(snapshot(next).generation, id(5));
    expect(
      () => first.begin(identity(host: id(6))),
      failure('RUNTIME_INCOMPATIBLE'),
    );
    expect(
      () => first.begin(
        JobObserverIdentity(
          jobId: id(1),
          attemptId: id(2),
          hostId: id(3),
          registryDigest: 'a' * 64,
          target: {...target(), 'workspaceId': id(7)},
        ),
      ),
      failure('RUNTIME_INCOMPATIBLE'),
    );
  });
  test('sequence floor, step, epoch and normalized same-sequence check facts are monotonic', () {
    final s = store(Clock()), b = s.begin(identity());
    s.observe(
      b,
      progress(
        1,
        checks: [
          {'checkId': 'c1', 'passed': true},
          {'checkId': 'c2', 'passed': false},
        ],
      ),
      currentTarget: target(),
    );
    expect(
      s.observe(
        b,
        progress(
          1,
          checks: [
            {'checkId': 'c2', 'passed': false},
            {'checkId': 'c1', 'passed': true},
          ],
        ),
        currentTarget: target(),
      ),
      isTrue,
    );
    s.observe(b, progress(2, step: 1, epoch: 1), currentTarget: target());
    expect(
      () =>
          s.observe(b, progress(3, step: 0, epoch: 1), currentTarget: target()),
      failure('RUNTIME_INCOMPATIBLE'),
    );
    expect(
      () =>
          s.observe(b, progress(3, step: 1, epoch: 0), currentTarget: target()),
      failure('RUNTIME_INCOMPATIBLE'),
    );
    s.advanceFloor(b, 9);
    s.advanceFloor(b, 2);
    expect(
      () =>
          s.observe(b, progress(8, step: 1, epoch: 1), currentTarget: target()),
      failure('RUNTIME_INCOMPATIBLE'),
    );
    expect(snapshot(s).lastSequence, 2);
  });
  test(
    'terminal and close detach while retaining only public sample facts',
    () {
      final s = store(Clock()), b = s.begin(identity());
      s.observe(b, progress(1, state: 'unknown'), currentTarget: target());
      expect(snapshot(s).state, JobObservationState.detached);
      expect(snapshot(s).lastSequence, 1);
      expect(snapshot(s).toJson().keys.toSet(), {
        'generation',
        'attemptId',
        'state',
        'lastSequence',
        'observedAt',
      });
      expect(s.observe(b, progress(2), currentTarget: target()), isFalse);
      final current = s.begin(identity());
      s.observe(current, progress(2), currentTarget: target());
      s.close();
      expect(snapshot(s).state, JobObservationState.detached);
      expect(s.observe(current, progress(3), currentTarget: target()), isFalse);
      expect(() => s.begin(identity()), failure('SERVICE_UNAVAILABLE'));
    },
  );
  test('1250retained jobs bound memory; pruning invalidates a removed active observer', () {
    final s = store(Clock());
    for (var n = 0; n < 1250; n++) {
      s.snapshot(
        jobId: id(n),
        attemptId: id(2000 + n),
        currentTarget: target(),
      );
    }
    final active = s.begin(identity(job: id(1), attempt: id(2001)));
    expect(s.count, 1250);
    expect(
      () => s.snapshot(
        jobId: id(1250),
        attemptId: id(3250),
        currentTarget: target(),
      ),
      failure('RESOURCE_LIMIT'),
    );
    s.prune({id(2)});
    expect(s.count, 1);
    expect(s.advanceFloor(active, 2), isFalse);
  });
}
