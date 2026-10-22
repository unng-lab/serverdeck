import 'dart:async';

import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/models.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson, graphDocument;
import 'mutations.dart' show GateProtection;

Future<StateStore> verifyFoundationCoordinator(
  StateStore store,
  Future<StateStore> Function() open,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  String mode,
) async {
  final graph = graphDocument(store.operational);
  final rows = store.operational.rows;
  MutationCoordinator create() => MutationCoordinator.operational(
    store,
    custody,
    key,
    clock: () => DateTime.utc(2000),
  );
  var coordinator = create();
  Map<String, Object?> settings() => {
    'expectedRevision': store.state.settings.revision,
    'theme': 'dark',
    'reduceMotion': true,
    'selectedProfileId': null,
  };
  Map<String, Object?> update({bool connection = false}) {
    final profile = store.state.profiles.values.single.toJson();
    return {
      'profileId': profile['id'],
      'expectedRevision': profile['revision'],
      for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
        field: profile[field],
      'name': 'Coordinator name',
      if (connection) 'address': 'coordinator-change.invalid',
      'credential': {'action': 'keep'},
    };
  }

  try {
    if (mode == 'coordinator-running') {
      await coordinator.close();
      final gate = GateProtection(custody.protection)
        ..reached = Completer<void>()
        ..release = Completer<void>();
      coordinator = MutationCoordinator.operational(
        store,
        KeyCustody(gate, custody.ownerSid),
        key,
      );
      final running = coordinator.submit(
        g.id(61900),
        ApiMethod.profilesUpdate,
        {
          ...update(),
          'credential': {
            'action': 'replace',
            'kind': 'password',
            'password': 'Synthetic coordinator credential',
          },
        },
        requester: 'running',
      );
      running.ignore();
      try {
        await gate.reached!.future.timeout(const Duration(seconds: 5));
        check(coordinator.status(g.id(61900)).state == MutationState.running);
        final tokens = [
          for (var i = 0; i < 31; i++)
            coordinator.reserve(
              g.id(61901 + i),
              ApiMethod.settingsUpdate,
              settings(),
              requester: 'queued',
            ),
        ];
        await refusal(
          () async => coordinator.reserve(
            g.id(61999),
            ApiMethod.settingsUpdate,
            settings(),
            requester: 'excess',
          ),
          'RESOURCE_LIMIT',
        );
        var drained = false;
        final closing = coordinator.close();
        closing.then((_) => drained = true).ignore();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        check(!drained);
        await refusal(() => tokens.first.result, 'SERVICE_UNAVAILABLE');
        gate.release!.complete();
        await running;
        await closing;
        check(
          drained &&
              store.state.receipts.containsKey(g.id(61900)) &&
              !store.state.receipts.containsKey(g.id(61901)),
        );
      } finally {
        if (!gate.release!.isCompleted) gate.release!.complete();
        await running;
      }
    } else if (mode == 'coordinator-reservation') {
      final input = settings(), id = g.id(62000);
      final first = coordinator.reserve(
        id,
        ApiMethod.settingsUpdate,
        input,
        requester: 'first',
      );
      input['theme'] = 'light';
      check(coordinator.status(id).state == MutationState.queued);
      final duplicate = coordinator.reserve(
        id,
        ApiMethod.settingsUpdate,
        settings(),
        requester: 'second',
      );
      check(identical(first.result, duplicate.result));
      final foreign = create();
      try {
        await refusal(() => foreign.activate(first), 'FORBIDDEN');
      } finally {
        await foreign.close();
      }
      await refusal(
        () async => coordinator.reserve(
          id,
          ApiMethod.settingsUpdate,
          input,
          requester: 'conflict',
        ),
        'IDEMPOTENCY_CONFLICT',
      );
      coordinator.detach('first');
      check(coordinator.status(id).state == MutationState.queued);
      final result = await coordinator.activate(duplicate);
      check((await first.result).storeRevision == result.storeRevision);
      check(store.state.settings.toJson()['theme'] == 'dark');
      check(coordinator.status(id).state == MutationState.committed);
      final cancelled = coordinator.reserve(
        g.id(62001),
        ApiMethod.settingsUpdate,
        settings(),
        requester: 'cancel',
      );
      coordinator.detach('cancel');
      check(coordinator.status(g.id(62001)).state == MutationState.notFound);
      await refusal(
        () => coordinator.activate(cancelled),
        'SERVICE_UNAVAILABLE',
      );
      final tokens = [
        for (var i = 0; i < 32; i++)
          coordinator.reserve(
            g.id(62100 + i),
            ApiMethod.settingsUpdate,
            settings(),
            requester: 'quota',
          ),
      ];
      await refusal(
        () async => coordinator.reserve(
          g.id(62999),
          ApiMethod.settingsUpdate,
          settings(),
          requester: 'excess',
        ),
        'RESOURCE_LIMIT',
      );
      await coordinator.close();
      await refusal(() => tokens.first.result, 'SERVICE_UNAVAILABLE');
      await refusal(() => coordinator.activate(tokens.first), 'NOT_READY');
      coordinator = create();
      check(coordinator.status(g.id(62100)).state == MutationState.notFound);
    } else if (mode == 'coordinator-active' || mode == 'coordinator-unknown') {
      final before = store.state.toJson();
      await refusal(
        () => coordinator.submit(
          g.id(63000),
          ApiMethod.profilesUpdate,
          update(connection: true),
          requester: 'occupied',
        ),
        'HOST_BUSY',
      );
      await refusal(
        () => coordinator.submit(g.id(63001), ApiMethod.profilesDelete, {
          'profileId': store.state.profiles.keys.single,
          'expectedRevision': store.state.profiles.values.single.revision,
        }, requester: 'occupied'),
        'HOST_BUSY',
      );
      sameJson(before, store.state.toJson(), 'coordinator-occupied-refusal');
      check(store.isAutomationReady);
      await coordinator.submit(
        g.id(63002),
        ApiMethod.profilesUpdate,
        update(),
        requester: 'metadata',
      );
      check(store.state.profiles.values.single.name == 'Coordinator name');
    } else {
      final id = g.id(64000), input = settings();
      final before = store.state.storeRevision;
      await refusal(
        () => coordinator.submit(g.id(64010), ApiMethod.settingsUpdate, {
          ...input,
          'expectedRevision': '9223372036854775808',
        }, requester: 'invalid'),
        'VALIDATION',
      );
      await refusal(
        () => coordinator.submit(
          g.id(64011),
          ApiMethod.settingsGet,
          {},
          requester: 'unsupported',
        ),
        'UNSUPPORTED',
      );
      check(
        store.isAutomationReady &&
            coordinator.status(g.id(64010)).state == MutationState.notFound,
      );
      final automationId = store.operational.automation.receipts.keys.first;
      await refusal(
        () => coordinator.submit(
          automationId,
          ApiMethod.settingsUpdate,
          input,
          requester: 'foreign-id',
        ),
        'IDEMPOTENCY_CONFLICT',
      );
      check(store.state.storeRevision == before);
      final committed = await coordinator.submit(
        id,
        ApiMethod.settingsUpdate,
        input,
        requester: 'owner',
      );
      check(
        (await coordinator.submit(
              id,
              ApiMethod.settingsUpdate,
              input,
              requester: 'replay',
            )).storeRevision ==
            committed.storeRevision,
      );
      await refusal(
        () => coordinator.submit(id, ApiMethod.settingsUpdate, {
          ...input,
          'theme': 'light',
        }, requester: 'conflict'),
        'IDEMPOTENCY_CONFLICT',
      );
      for (final receipt in store.operational.automation.receipts.values) {
        check(
          !DateTime.parse(store.state.receipts[id]!.committedAt)
              .isBefore(receipt.createdAt),
        );
      }
      await coordinator.submit(
        g.id(64001),
        ApiMethod.profilesUpdate,
        update(),
        requester: 'owner',
      );
      final legacy = MutationCoordinator(store, custody, key);
      try {
        await refusal(
          () => legacy.submit(
            g.id(64002),
            ApiMethod.settingsUpdate,
            settings(),
            requester: 'legacy',
          ),
        );
      } finally {
        await legacy.close();
      }
      check(store.isAutomationReady);
    }
  } finally {
    await coordinator.close();
  }
  sameJson(
    graph,
    graphDocument(store.operational),
    'coordinator-retained-graph',
  );
  for (final name in rows.keys) {
    sameJson(
      [
        for (final row in rows[name]!)
          [row.nativeId, row.entityId, row.payload],
      ],
      [
        for (final row in store.operational.rows[name]!)
          [row.nativeId, row.entityId, row.payload],
      ],
      'coordinator-retained-$name',
    );
  }
  final committed = store.state.toJson();
  await store.close();
  store = await open();
  sameJson(committed, store.state.toJson(), 'coordinator-reopen');
  sameJson(graph, graphDocument(store.operational), 'coordinator-reopen-graph');
  check(store.isAutomationReady);
  return store;
}
