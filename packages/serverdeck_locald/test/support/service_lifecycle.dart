import 'dart:async';
import 'dart:io';

import 'package:serverdeck_locald/bootstrap/lifecycle.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/mutex.dart';

import '../models_test.dart' as fixture;
import '../lifecycle_test.dart' show ManualDeadlines, sessionId;
import 'mutations.dart' show GateProtection;
import 'state_store_child.dart' show check, rejects;

Future<void> verifyServiceLifecycle(
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  MutexLease lease,
  String name,
  String root,
  String directory,
  String bundle,
) async {
  final wrapper = List<int>.of(key.wrapper);
  final gate = GateProtection(custody.protection);
  final coordinator = MutationCoordinator(
    store,
    KeyCustody(gate, custody.ownerSid),
    key,
  );
  final clock = ManualDeadlines(), order = <String>[];
  final lifecycle = ServiceLifecycle(
    generation: fixture.workspace,
    elapsed: () => clock.now,
    schedule: clock.schedule,
    onDetached: coordinator.detach,
    resources: ShutdownResources(
      cancelStartup: () async {
        order.add('cancel-startup');
      },
      drainMutations: () async {
        order.add('drain');
        await coordinator.close();
      },
      closeStorage: () async {
        order.add('storage');
        await store.close();
      },
      closePipes: () async {
        order.add('pipes-fixture-noop');
      },
      removeDiscovery: () async {
        order.add('discovery-fixture-noop');
      },
      clearKeys: () async {
        order.add('keys');
        key.close();
      },
      releaseMutex: () async {
        order.add('mutex');
        await lease.close();
      },
    ),
  );
  try {
    lifecycle.bootstrapComplete();
    final requester = sessionId(1);
    lifecycle.sessions.register(
      'fixture',
      requester,
      Capability.values.toSet(),
    );
    final create = {
      'profileId': fixture.profileId,
      'name': 'Synthetic',
      'address': 'example.invalid',
      'sshUser': 'synthetic',
    };
    const first = 'c2345678-1234-4234-8234-000000000001';
    const runningId = 'c2345678-1234-4234-8234-000000000002';
    const queuedId = 'c2345678-1234-4234-8234-000000000003';
    await coordinator.submit(
      first,
      ApiMethod.profilesCreate,
      create,
      requester: requester,
    );
    gate.reached = Completer<void>();
    gate.release = Completer<void>();
    final running = coordinator.submit(runningId, ApiMethod.profilesUpdate, {
      ...create,
      'expectedRevision': '1',
      'port': 22,
      'tags': <String>[],
      'credential': {
        'action': 'replace',
        'kind': 'password',
        'password': 'synthetic-service-lifecycle',
      },
    }, requester: requester);
    await gate.reached!.future.timeout(const Duration(seconds: 5));
    final queued = rejects(
      coordinator.submit(queuedId, ApiMethod.settingsUpdate, {
        'expectedRevision': '1',
        'theme': 'dark',
        'reduceMotion': true,
        'selectedProfileId': null,
      }, requester: requester),
      'SERVICE_UNAVAILABLE',
    );
    final closed = lifecycle.close();
    await queued;
    await Future<void>.delayed(Duration.zero);
    check(order.join(',') == 'cancel-startup,drain');
    check(lease.isHeld && store.state.storeRevision == '1');
    gate.release!.complete();
    final result = await running;
    check(result.storeRevision == '2');
    await closed;
    check(
      order.join(',') == 'cancel-startup,drain,storage,pipes-fixture-noop,discovery-fixture-noop,keys,mutex',
    );
    check(!lease.isHeld);
    await rejects(custody.receiptDigest(key, {}), 'STORAGE_BLOCKED');
    final nextLease = await MutexLease.acquire(name, custody.ownerSid);
    ReceiptKeyMaterial? reopenedKey;
    StateStore? reopened;
    try {
      check(nextLease.isHeld);
      reopenedKey = await custody.openReceiptKey(
        wrapper,
        fixture.workspace,
        fixture.receiptKeyId,
      );
      reopened = await StateStore.open(
        localAppData: root,
        directory: directory,
        appRoot: bundle,
        lease: nextLease,
        custody: custody,
        receiptKey: reopenedKey,
      );
      check(reopened.state.storeRevision == '2');
      check(reopened.state.receipts.containsKey(runningId));
      check(!reopened.state.receipts.containsKey(queuedId));
      check(reopened.state.settings.revision == '1');
      final record = reopened.state.credentials.values.single;
      final secret = await custody.openCredential(
        record.protectedBlob,
        fixture.workspace,
        fixture.profileId,
        record.id,
      );
      check(secret['password'] == 'synthetic-service-lifecycle');
      secret.clear();
    } finally {
      await reopened?.close();
      reopenedKey?.close();
      await nextLease.close();
    }
    stdout.writeln('NATIVE_LIFECYCLE_DRAIN_REOPEN_PROVED');
  } finally {
    if (gate.release != null && !gate.release!.isCompleted)
      gate.release!.complete();
    await lifecycle.close();
  }
}
