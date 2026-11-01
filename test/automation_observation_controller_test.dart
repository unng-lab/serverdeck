import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_protocol/automation/job_observation.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';

import '../lib/automation/automation_controller.dart';
import '../lib/bootstrap/engine_client.dart';

String id(int n) =>
    '12345678-1234-4234-9234-12345678b${n.toRadixString(16).padLeft(3, '0')}';
final generation = id(1), server = id(2), first = id(3), second = id(4);
// Structural presentation fixtures, not native authority or remote outcome proof.
Map<String, Object?> job(
  String key, {
  String state = 'running',
  String? attempt,
}) => AutomationJobRecord.fromJson({
  'workspaceId': id(5),
  'id': key,
  'requestId': id(6),
  'immutablePlanId': id(7),
  'planDigest': 'a' * 64,
  'profileId': id(8),
  'profileRevision': 1,
  'profileDigest': 'b' * 64,
  'grantId': null,
  'authorityRef': {'kind': 'approval', 'id': id(9), 'revision': 1},
  'hostAttemptId': attempt ?? id(key == first ? 10 : 11),
  'state': state,
  'nextSequence': 10,
  'cancelRequested': false,
  'createdAt': '2026-10-31T10:00:00.000Z',
  'updatedAt': '2026-10-31T10:00:00.000Z',
  'outcome': state == 'unknown'
      ? {'effects': 'uncertain', 'checks': [], 'safeCode': 'UNKNOWN_OUTCOME'}
      : state == 'succeeded'
      ? {'effects': 'none', 'checks': [], 'safeCode': null}
      : null,
}).toJson();
Map<String, Object?> observation(
  Map<String, Object?> j, {
  bool sample = true,
}) => {
  'generation': generation,
  'attemptId': j['hostAttemptId'],
  'state': sample ? 'attached' : 'detached',
  'lastSequence': sample ? 7 : null,
  'observedAt': sample ? '2026-10-31T10:00:00.000Z' : null,
};
Map<String, Object?> row(Map<String, Object?> j, {bool sample = true}) => {
  'job': j,
  'serverId': server,
  'observation': observation(j, sample: sample),
};

final class Tick {
  Tick(this.action);
  final void Function() action;
  bool cancelled = false;
  bool fired = false;
  void fire() {
    fired = true;
    action();
  }
}

final class Gateway implements EngineGateway {
  @override
  String generation = id(1);
  @override
  bool isClosed = false;
  final retirement = Completer<void>();
  @override
  Future<void> get retired => retirement.future;
  final calls = <String>[];
  final rows = <Map<String, Object?>>[row(job(first)), row(job(second))];
  String? failMethod, holdMethod;
  Completer<void>? hold;
  @override
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) async {
    calls.add(method);
    if (failMethod == method) throw EngineCallFailure('TIMEOUT');
    if (method == 'automation.cancel')
      return {'operationId': params['operationId'], 'cancelled': true};
    final data = switch (method) {
      'jobs.list' => <String, Object?>{'items': rows},
      'jobs.get' => () {
        final r = rows.firstWhere(
          (r) => (r['job'] as Map)['id'] == params['jobId'],
        );
        return <String, Object?>{
          'job': r['job'],
          'plan': {'serverId': server},
          'observation': r['observation'],
        };
      }(),
      'jobs.events' => <String, Object?>{
        'events': <Object?>[],
        'nextSequence': 10,
        'dropped': 0,
        'hasMore': false,
      },
      _ => throw StateError('UNDECLARED_CONTROLLER_METHOD'),
    };
    final captured = jsonDecode(jsonEncode(data)) as Map<String, Object?>;
    if (holdMethod == method) await hold?.future;
    return {
      'operationId': requestId,
      'state': 'done',
      'kind': method,
      'result': McpToolResult.success(captured).toJson(),
    };
  }

  @override
  Future<void> close() async {
    isClosed = true;
    if (!retirement.isCompleted) retirement.complete();
  }
}

final class Setup {
  final gateway = Gateway(), ticks = <Tick>[];
  late final client = EngineClient(gateway);
  late final model = AutomationController(
    client: client,
    serverId: server,
    schedule: (delay, fire) {
      expect(delay, const Duration(seconds: 1));
      final tick = Tick(fire);
      ticks.add(tick);
      return () => tick.cancelled = true;
    },
  );
  Setup() {
    addTearDown(() {
      model.dispose();
    });
  }
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void noControl(Gateway g) => expect(
  g.calls.where(
    (m) => {'jobs.apply', 'jobs.cancel', 'jobs.reconcile'}.contains(m),
  ),
  isEmpty,
);

void main() {
  test(
    'failed event read does not partially select a new remote job',
    () async {
      final s = Setup();
      await s.model.selectJob(first);
      final previous = jsonDecode(jsonEncode(s.model.job));
      s.gateway.failMethod = 'jobs.events';
      await s.model.selectJob(second);
      expect(s.model.error, 'TIMEOUT');
      expect(s.model.job, previous);
      expect(s.model.jobObservation!.attemptId, previous['hostAttemptId']);
      expect(s.model.jobObservation!.state, JobObservationState.stale);
      noControl(s.gateway);
    },
  );
  test('a fired timer during an active read cannot overlap dispatch or duplicate the next poll', () async {
    final s = Setup();
    await s.model.selectJob(first);
    final timer = s.ticks.last;
    s.gateway.holdMethod = 'jobs.list';
    final release = s.gateway.hold = Completer<void>();
    final read = s.model.refreshJobs();
    await settle();
    final count = s.gateway.calls.length;
    timer.fire();
    await settle();
    expect(s.gateway.calls.length, count);
    release.complete();
    await read;
    expect(s.ticks.where((t) => !t.cancelled && !t.fired), hasLength(1));
    noControl(s.gateway);
  });
  test('listed and selected observations are separate typed data alongside unchanged remote outcome', () async {
    final s = Setup();
    await s.model.refreshJobs();
    await s.model.selectJob(first);
    expect(s.model.jobObservation!.state, JobObservationState.attached);
    expect(s.model.jobObservations.keys.toSet(), {first, second});
    expect(
      s.model.jobObservations[first]!.attemptId,
      s.model.job!['hostAttemptId'],
    );
    expect(s.model.job!['state'], 'running');
    expect(s.model.job!.containsKey('observation'), isFalse);
    expect(s.model.jobs.first.containsKey('observation'), isFalse);
    expect(s.model.jobObservation!.lastSequence, 7);
    noControl(s.gateway);
  });
  for (final fault in ['generation', 'attempt', 'state', 'extra']) {
    test(
      'bad $fault observation rejects read without replacing retained remote result',
      () async {
        final s = Setup();
        await s.model.selectJob(first);
        final old = jsonDecode(jsonEncode(s.model.job));
        final view =
            s.gateway.rows.first['observation'] as Map<String, Object?>;
        switch (fault) {
          case 'generation':
            view['generation'] = id(12);
          case 'attempt':
            view['attemptId'] = id(13);
          case 'state':
            view['state'] = 'PRIVATE_INVALID_STATE';
          case 'extra':
            view['owner'] = true;
        }
        await s.model.selectJob(first);
        expect(s.model.error, 'INCOMPATIBLE');
        expect(s.model.job, old);
        expect(s.model.jobObservation!.state, JobObservationState.stale);
        expect(s.model.canRetry, isFalse);
        noControl(s.gateway);
      },
    );
  }
  for (final sample in [false, true]) {
    test(
      'read loss marks sample=$sample stale or detached without changing succeeded',
      () async {
        final s = Setup();
        s.gateway.rows
          ..clear()
          ..add(row(job(first, state: 'succeeded'), sample: sample));
        await s.model.refreshJobs();
        await s.model.selectJob(first);
        final old = jsonDecode(jsonEncode(s.model.job));
        s.gateway.failMethod = 'jobs.list';
        await s.model.refreshJobs();
        expect(s.model.error, 'TIMEOUT');
        expect(s.model.job, old);
        expect(s.model.job!['state'], 'succeeded');
        expect(
          s.model.jobObservation!.state,
          sample ? JobObservationState.stale : JobObservationState.detached,
        );
        expect(
          s.model.jobObservations[first]!.state,
          s.model.jobObservation!.state,
        );
        noControl(s.gateway);
      },
    );
  }
  test(
    'client loss detaches selected and listed samples and keeps remote result',
    () async {
      final s = Setup();
      await s.model.refreshJobs();
      await s.model.selectJob(first);
      final old = jsonDecode(jsonEncode(s.model.job));
      await s.gateway.close();
      await settle();
      expect(s.model.job, old);
      expect(s.model.jobObservation!.state, JobObservationState.detached);
      expect(
        s.model.jobObservations.values.every(
          (v) => v.state == JobObservationState.detached,
        ),
        isTrue,
      );
      expect(s.model.jobObservation!.lastSequence, 7);
      expect(s.model.canMutate, isFalse);
      expect(s.ticks.last.cancelled, isTrue);
      noControl(s.gateway);
    },
  );
  test(
    'list capture is atomic when a later row has another generation',
    () async {
      final s = Setup();
      await s.model.refreshJobs();
      final old = jsonDecode(jsonEncode(s.model.jobs));
      s.gateway.rows
        ..clear()
        ..add(row(job(second)))
        ..add(row(job(id(14))));
      (s.gateway.rows.last['observation'] as Map)['generation'] = id(15);
      await s.model.refreshJobs();
      expect(s.model.error, 'INCOMPATIBLE');
      expect(s.model.jobs, old);
      expect(s.model.jobObservations.keys.toSet(), {first, second});
      noControl(s.gateway);
    },
  );
  test('new matching pair cannot substitute another attempt for an already known job', () async {
    final s = Setup();
    await s.model.selectJob(first);
    final old = jsonDecode(jsonEncode(s.model.job));
    s.gateway.rows[0] = row(job(first, attempt: id(16)));
    await s.model.selectJob(first);
    expect(s.model.error, 'INCOMPATIBLE');
    expect(s.model.job, old);
    noControl(s.gateway);
  });
  test(
    'retired timer cannot select the previous job or dispatch a control',
    () async {
      final s = Setup();
      await s.model.selectJob(first);
      final retired = s.ticks.last;
      await s.model.selectJob(second);
      final current = s.ticks.last, count = s.gateway.calls.length;
      retired.fire();
      await settle();
      expect(s.gateway.calls.length, count);
      expect(s.model.job!['id'], second);
      current.fire();
      await settle();
      expect(s.model.job!['id'], second);
      expect(s.gateway.calls.length, count + 2);
      noControl(s.gateway);
    },
  );
  test(
    'dispose rejects an already captured delayed read and retires its timer',
    () async {
      final s = Setup();
      await s.model.selectJob(first);
      final old = jsonDecode(jsonEncode(s.model.job));
      s.gateway.holdMethod = 'jobs.get';
      final release = s.gateway.hold = Completer<void>();
      final read = s.model.selectJob(second);
      await settle();
      s.model.dispose();
      release.complete();
      await read;
      expect(s.model.job, old);
      expect(s.ticks.every((t) => t.cancelled), isTrue);
      expect(s.model.jobObservation!.state, JobObservationState.detached);
      noControl(s.gateway);
    },
  );
  test('generation changed during read cannot install it or keep mutation actions enabled', () async {
    final s = Setup();
    await s.model.selectJob(first);
    final old = jsonDecode(jsonEncode(s.model.job));
    s.gateway.holdMethod = 'jobs.get';
    final release = s.gateway.hold = Completer<void>();
    final read = s.model.selectJob(second);
    await settle();
    s.gateway.generation = id(17);
    release.complete();
    await read;
    expect(s.model.job, old);
    expect(s.model.jobObservation!.state, JobObservationState.detached);
    expect(s.model.canMutate, isFalse);
    expect(s.model.canRetry, isFalse);
    noControl(s.gateway);
  });
}
