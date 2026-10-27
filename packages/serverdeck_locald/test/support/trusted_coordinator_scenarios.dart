import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_locald/storage/host_trust_models.dart';
import 'package:serverdeck_locald/storage/models.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_windows/mutex.dart';

import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/profiles/host_trust.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/models.dart';

import '../automation/snapshot_test.dart' as g;
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check, sameJson;
import 'mutations.dart' show GateProtection;

Future<void> exerciseTrustedCoordinator(
  String root,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  MutexLease lease,
  String mode,
) async {
  Future<StateStore> open() => StateStore.openTrustedOperational(
    localAppData: root,
    appRoot: root,
    custody: custody,
    receiptKey: key,
    lease: lease,
  );
  var store = await open();
  try {
    Map<String, Object?> graphDocument() => {
      for (final e in store.trustedOperational.rows.entries)
        if (!const {
          'StoredWorkspace',
          'StoredProfile',
          'StoredSettings',
          'StoredCredential',
          'StoredReceipt',
          'StoredHostTrust',
        }.contains(e.key))
          e.key: [
            for (final r in e.value) [r.nativeId, r.entityId, r.payload],
          ],
    };
    final graph = graphDocument();
    final rows = Map.fromEntries(
      store.trustedOperational.rows.entries.where(
        (e) => graphDocument().containsKey(e.key),
      ),
    );
    check(rows.length == 10 && rows.values.every((v) => v.isNotEmpty));
    TrustedMutationCoordinator create() => TrustedMutationCoordinator(
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
      if (mode == 'coordinator-create') {
        final id = g.id(66000), request = g.id(66001);
        final input = <String, Object?>{
          'profileId': id,
          'name': 'New trusted profile',
          'address': 'new.invalid',
          'sshUser': 'synthetic',
          'credential': {
            'action': 'replace',
            'kind': 'password',
            'password': 'Synthetic new credential',
          },
        };
        final created = await coordinator.submit(
          request,
          ApiMethod.profilesCreate,
          input,
          requester: 'create',
        );
        check(
          created.entityRevision == '1' &&
              store.state.profiles[id]!.trustRevision == '1' &&
              !store.trustedOperational.foundation.trust.containsKey(id),
        );
        final profile = store.state.profiles[id]!.toJson();
        await coordinator.submit(g.id(66002), ApiMethod.profilesUpdate, {
          'profileId': id,
          'expectedRevision': '1',
          for (final f in ['name', 'address', 'port', 'sshUser', 'tags'])
            f: profile[f],
          'address': 'changed-new.invalid',
          'credential': {'action': 'keep'},
        }, requester: 'change');
        check(
          store.state.profiles[id]!.connectionRevision == '2' &&
              store.state.profiles[id]!.trustRevision == '2' &&
              !store.trustedOperational.foundation.trust.containsKey(id),
        );
        await coordinator.submit(g.id(66003), ApiMethod.settingsUpdate, {
          ...settings(),
          'selectedProfileId': id,
        }, requester: 'settings');
        await coordinator.submit(g.id(66004), ApiMethod.profilesDelete, {
          'profileId': id,
          'expectedRevision': '2',
        }, requester: 'delete');
        check(
          store.state.settings.selectedProfileId == null &&
              !store.state.profiles.containsKey(id),
        );
        check(
          (await coordinator.submit(
                request,
                ApiMethod.profilesCreate,
                input,
                requester: 'replay',
              )).storeRevision ==
              created.storeRevision,
        );
        check(!store.state.profiles.containsKey(id));
        await refusal(
          () => coordinator.submit(
            g.id(66005),
            ApiMethod.profilesCreate,
            input,
            requester: 'resurrect',
          ),
          'ALREADY_EXISTS',
        );
      } else if (mode == 'coordinator-key') {
        check(coordinator.isTrusted && !coordinator.isOperational);
        final wrong = await custody.createReceiptKey(
          key.workspaceId,
          key.receiptKeyId,
        );
        try {
          await refusal(
            () async => TrustedMutationCoordinator(store, custody, wrong),
            'STORAGE_BLOCKED',
          );
        } finally {
          wrong.close();
        }
        await refusal(
          () async => TrustedMutationCoordinator(store, custody, wrong),
          'STORAGE_BLOCKED',
        );
        await refusal(
          () async => MutationCoordinator.operational(store, custody, key),
          'STORAGE_BLOCKED',
        );
        check(store.isTrustedSnapshotLoaded);
      } else if (mode == 'coordinator-trust-preparation') {
        final profile = store.state.profiles.values.single;
        final pin = {
          'format': 'ssh-ed25519',
          'fingerprint':
              'SHA256:${base64.encode(List.filled(32, 6)).replaceAll('=', '')}',
        };
        int? nativeId;
        var sequence = 0;
        // Internal transition/storage qualification, without owner admission
        // or challenge consumption. The production coordinator is not wired.
        for (final method in [
          'servers.trust.confirm',
          'servers.trust.revoke',
          'servers.trust.revoke',
          'servers.trust.confirm',
        ]) {
          final current = store.state.profiles[profile.id]!;
          final body = <String, Object?>{
            'profileId': profile.id,
            'expectedRevision': current.revision,
            if (method == 'servers.trust.confirm') ...{
              'challengeId': g.id(67010),
              'key': pin,
            },
          };
          final prepared = prepareHostTrustMutation(
            store.trustedOperational.foundation,
            method,
            body,
            g.finished,
          );
          final request = g.id(67000 + sequence++);
          (prepared.value['receipts'] as Map)[request] = {
            'requestId': request,
            'inputDigest': custody.receiptDigestSync(key, {
              'operation': method,
              'params': body,
            }),
            'operation': method,
            'profileId': profile.id,
            'result': prepared.result.toJson(),
            'committedAt': g.finished,
          };
          await store.commitTrustedFoundation(
            HostTrustState.fromRecords(
              WorkspaceState.fromTrustedJson(
                prepared.value,
                workspaceId: key.workspaceId,
                receiptKeyId: key.receiptKeyId,
                ownerSid: key.ownerSid,
              ),
              prepared.trust,
            ),
          );
          final row = store.trustedOperational.rows['StoredHostTrust']!.single;
          nativeId ??= row.nativeId;
          check(row.nativeId == nativeId);
          final trusted =
              store.trustedOperational.foundation.trust[profile.id]!;
          check(trusted.createdAt == g.finished);
          check(
            trusted.status ==
                (method == 'servers.trust.confirm'
                    ? HostTrustStatus.trusted
                    : HostTrustStatus.revoked),
          );
          check(
            store.state.profiles[profile.id]!.connectionRevision ==
                profile.connectionRevision,
          );
          check(
            store.state.profiles[profile.id]!.credentialRevision ==
                profile.credentialRevision,
          );
          sameJson(pin, trusted.key.toJson(), 'prepared-pin');
          await store.close();
          store = await open();
          check(
            store.trustedOperational.rows['StoredHostTrust']!.single.nativeId ==
                nativeId,
          );
          sameJson(
            trusted.toJson(),
            store.trustedOperational.foundation.trust[profile.id]!.toJson(),
            'prepared-reopen',
          );
        }
      } else if (mode == 'coordinator-trust') {
        final profile = store.state.profiles.values.single;
        final stamp = g.finished;
        final doc = store.state.toJson()
          ..['storeRevision'] = nextRevision(store.state.storeRevision);
        final nextProfile = {
          ...profile.toJson(),
          'revision': nextRevision(profile.revision),
          'trustRevision': nextRevision(profile.trustRevision),
          'updatedAt': stamp,
        };
        (doc['profiles'] as Map)[profile.id] = nextProfile;
        final pin = {
          'format': 'ssh-ed25519',
          'fingerprint':
              'SHA256:${base64.encode(List.filled(32, 5)).replaceAll('=', '')}',
        };
        final request = g.id(65000);
        final body = {
          'profileId': profile.id,
          'expectedRevision': profile.revision,
          'challengeId': g.id(65001),
          'key': pin,
        };
        (doc['receipts'] as Map)[request] = {
          'requestId': request,
          'inputDigest': custody.receiptDigestSync(key, {
            'operation': 'servers.trust.confirm',
            'params': body,
          }),
          'operation': 'servers.trust.confirm',
          'profileId': profile.id,
          'result': {
            'entityId': profile.id,
            'entityRevision': nextProfile['revision'],
            'storeRevision': doc['storeRevision'],
            'deleted': false,
          },
          'committedAt': stamp,
        };
        final trust = HostTrustRecord.fromJson({
          'workspaceId': key.workspaceId,
          'profileId': profile.id,
          'revision': nextProfile['trustRevision'],
          'connectionRevision': profile.connectionRevision,
          'status': 'trusted',
          'key': pin,
          'createdAt': stamp,
          'updatedAt': stamp,
        });
        // Internal storage setup only: not a claim of owner challenge admission.
        await store.commitTrustedFoundation(
          HostTrustState.fromRecords(
            WorkspaceState.fromTrustedJson(
              doc,
              workspaceId: key.workspaceId,
              receiptKeyId: key.receiptKeyId,
              ownerSid: key.ownerSid,
            ),
            {profile.id: trust},
          ),
        );
        final rawTrust =
            store.trustedOperational.rows['StoredHostTrust']!.single;
        await coordinator.submit(
          g.id(65002),
          ApiMethod.profilesUpdate,
          update(),
          requester: 'metadata',
        );
        check(
          store.state.profiles[profile.id]!.trustRevision == trust.revision,
        );
        sameJson(
          trust.toJson(),
          store.trustedOperational.foundation.trust[profile.id]!.toJson(),
          'metadata-trust',
        );
        check(
          store.trustedOperational.rows['StoredHostTrust']!.single.payload ==
              rawTrust.payload,
        );
        await coordinator.submit(g.id(65003), ApiMethod.profilesUpdate, {
          ...update(),
          'credential': {
            'action': 'replace',
            'kind': 'password',
            'password': 'Synthetic trusted coordinator',
          },
        }, requester: 'credential');
        sameJson(
          trust.toJson(),
          store.trustedOperational.foundation.trust[profile.id]!.toJson(),
          'credential-trust',
        );
        check(
          store.trustedOperational.rows['StoredHostTrust']!.single.nativeId ==
              rawTrust.nativeId,
        );
        await coordinator.submit(
          g.id(65004),
          ApiMethod.profilesUpdate,
          update(connection: true),
          requester: 'connection',
        );
        final revoked = store.trustedOperational.foundation.trust[profile.id]!;
        check(
          revoked.status == HostTrustStatus.revoked &&
              revoked.revision == nextRevision(trust.revision) &&
              revoked.connectionRevision == trust.connectionRevision &&
              revoked.createdAt == trust.createdAt,
        );
        sameJson(revoked.key.toJson(), pin, 'retained-pin');
        check(
          store.state.profiles[profile.id]!.connectionRevision ==
              nextRevision(profile.connectionRevision),
        );
        await coordinator.close();
        await store.close();
        store = await open();
        coordinator = create();
        sameJson(
          revoked.toJson(),
          store.trustedOperational.foundation.trust[profile.id]!.toJson(),
          'revoked-reopen',
        );
        check(
          store.trustedOperational.rows['StoredHostTrust']!.single.nativeId ==
              rawTrust.nativeId,
        );
        check(
          coordinator.recent().receipts.any(
            (r) => r.operation == 'servers.trust.confirm',
          ),
        );
        await coordinator.submit(g.id(65005), ApiMethod.profilesDelete, {
          'profileId': profile.id,
          'expectedRevision': store.state.profiles[profile.id]!.revision,
        }, requester: 'delete');
        check(
          store.trustedOperational.foundation.trust.isEmpty &&
              store.state.profiles.isEmpty &&
              coordinator.status(request).state == MutationState.committed,
        );
      } else if (mode == 'coordinator-running') {
        await coordinator.close();
        final gate = GateProtection(custody.protection)
          ..reached = Completer<void>()
          ..release = Completer<void>();
        coordinator = TrustedMutationCoordinator(
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
      } else if (mode == 'coordinator-active' ||
          mode == 'coordinator-unknown') {
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
        check(store.isTrustedSnapshotLoaded);
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
          store.isTrustedSnapshotLoaded &&
              coordinator.status(g.id(64010)).state == MutationState.notFound,
        );
        final automationId =
            store.trustedOperational.automation.receipts.keys.first;
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
        for (final receipt
            in store.trustedOperational.automation.receipts.values) {
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
        check(store.isTrustedSnapshotLoaded);
      }
    } finally {
      await coordinator.close();
    }
    sameJson(graph, graphDocument(), 'coordinator-retained-graph');
    for (final name in rows.keys) {
      sameJson(
        [
          for (final row in rows[name]!)
            [row.nativeId, row.entityId, row.payload],
        ],
        [
          for (final row in store.trustedOperational.rows[name]!)
            [row.nativeId, row.entityId, row.payload],
        ],
        'coordinator-retained-$name',
      );
    }
    final committed = store.state.toJson();
    await store.close();
    store = await open();
    sameJson(committed, store.state.toJson(), 'coordinator-reopen');
    sameJson(graph, graphDocument(), 'coordinator-reopen-graph');
    check(store.isTrustedSnapshotLoaded);
  } finally {
    await store.close();
  }
}
