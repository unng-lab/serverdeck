import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/profiles/service.dart';
import 'package:serverdeck_locald/credentials/provider.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:serverdeck_windows/security.dart';

import '../models_test.dart' as fixture;
import 'state_store_child.dart' show check, rejects;

class GateProtection implements UserProtection {
  GateProtection(this.delegate);
  final UserProtection delegate;
  Completer<void>? reached, release;
  bool fail = false;
  @override
  Future<List<int>> protect(List<int> value, List<int> entropy) async {
    reached?.complete();
    await release?.future;
    if (fail) throw StateError('PROTECTION_UNAVAILABLE');
    return delegate.protect(value, entropy);
  }

  @override
  Future<List<int>> unprotect(List<int> value, List<int> entropy) =>
      delegate.unprotect(value, entropy);
}

Future<void> verifyMutations(
  StateStore initial,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  Future<StateStore> Function() open,
) async {
  StateStore? store = initial;
  var coordinator = MutationCoordinator(store, custody, key);
  var number = 0;
  String request() =>
      '62345678-1234-4234-8234-${(++number).toRadixString(16).padLeft(12, '0')}';
  final create = <String, Object?>{
    'profileId': fixture.profileId,
    'name': 'Synthetic',
    'address': 'example.invalid',
    'sshUser': 'synthetic',
  };
  Map<String, Object?> update(
    String revision,
    Map<String, Object?> credential,
  ) => {
    ...create,
    'expectedRevision': revision,
    'port': 22,
    'tags': <String>[],
    'credential': credential,
  };
  Future<MutationResult> submit(
    String id,
    ApiMethod method,
    Map<String, Object?> input, [
    String requester = 'owned-a',
  ]) => coordinator.submit(id, method, input, requester: requester);
  try {
    final firstId = request();
    check(coordinator.status(firstId).state == MutationState.notFound);
    final original = submit(firstId, ApiMethod.profilesCreate, create);
    check(coordinator.status(firstId).state == MutationState.queued);
    final duplicate = submit(
      firstId,
      ApiMethod.profilesCreate,
      create,
      'owned-b',
    );
    check(identical(original, duplicate));
    await rejects(
      submit(firstId, ApiMethod.profilesCreate, {
        ...create,
        'name': 'Different',
      }),
      'IDEMPOTENCY_CONFLICT',
    );
    final result =
        await duplicate; // Lost original reply: same request still one effect.
    check(result.entityRevision == '1' && store.state.storeRevision == '1');
    check(coordinator.status(firstId).state == MutationState.committed);
    await rejects(
      submit(request(), ApiMethod.profilesCreate, create),
      'ALREADY_EXISTS',
    );
    final password = {
      'action': 'replace',
      'kind': 'password',
      'password': ' e\u0301 synthetic ',
    };
    final replacement = request();
    final replaced = await submit(
      replacement,
      ApiMethod.profilesUpdate,
      update('1', password),
    );
    check(replaced.entityRevision == '2');
    final firstCredential =
        store.state.profiles[fixture.profileId]!.credentialRef!;
    check(store.state.credentials[firstCredential]!.revision == '2');
    check(
      (await custody.openCredential(
            store.state.credentials[firstCredential]!.protectedBlob,
            fixture.workspace,
            fixture.profileId,
            firstCredential,
          ))['password'] ==
          password['password'],
    );
    final conflict = request();
    await rejects(
      submit(
        conflict,
        ApiMethod.profilesUpdate,
        update('1', {'action': 'keep'}),
      ),
      'REVISION_CONFLICT',
    );
    check(
      coordinator.status(conflict).state == MutationState.notFound &&
          store.state.storeRevision == '2',
    );
    await submit(
      request(),
      ApiMethod.profilesUpdate,
      update('2', {'action': 'remove'}),
    );
    check(
      store.state.credentials.isEmpty &&
          store.state.profiles[fixture.profileId]!.credentialRevision == '3',
    );
    await submit(request(), ApiMethod.profilesUpdate, update('3', password));
    final record = store.state.credentials.values.single;
    check(record.id != firstCredential && record.revision == '4');
    final kept = await submit(request(), ApiMethod.profilesUpdate, {
      ...update('4', {'action': 'keep'}),
      'name': 'Renamed',
    });
    check(kept.entityRevision == '5');
    check(
      store.state.credentials.values.single.protectedBlob ==
          record.protectedBlob,
    );
    final views = ProfileService(CredentialProvider(custody));
    final view = views.list(store.state).toJson().toString();
    check(
      !view.contains('protectedBlob') &&
          !view.contains('credentialRef') &&
          !view.contains('synthetic '),
    );
    await submit(request(), ApiMethod.settingsUpdate, {
      'expectedRevision': '1',
      'theme': 'dark',
      'reduceMotion': true,
      'selectedProfileId': fixture.profileId,
    });
    final deletion = await submit(request(), ApiMethod.profilesDelete, {
      'profileId': fixture.profileId,
      'expectedRevision': '5',
    });
    check(deletion.deleted && deletion.entityRevision == '5');
    check(store.state.profiles.isEmpty && store.state.credentials.isEmpty);
    check(
      store.state.settings.revision == '3' &&
          store.state.settings.toJson()['selectedProfileId'] == null,
    );
    final beforeReplay = store.state.storeRevision;
    check(
      (await submit(firstId, ApiMethod.profilesCreate, create)).storeRevision ==
          '1',
    );
    check(store.state.storeRevision == beforeReplay);
    await coordinator.close();
    await store.close();
    store = null;
    store = await open();
    coordinator = MutationCoordinator(store, custody, key);
    check(
      (await submit(
            replacement,
            ApiMethod.profilesUpdate,
            update('1', password),
          )).storeRevision ==
          '2',
    );
    check(
      store.state.profiles.isEmpty,
    ); // Historical success never recreates deleted entity.
    check(coordinator.recent(limit: 1).truncated);
    final cancelled = request();
    final cancelledResult = rejects(
      submit(cancelled, ApiMethod.profilesCreate, create),
      'SERVICE_UNAVAILABLE',
    );
    coordinator.detach('owned-a');
    check(coordinator.status(cancelled).state == MutationState.notFound);
    await cancelledResult;
    await submit(cancelled, ApiMethod.profilesCreate, create);
    final retained = request();
    final a = submit(
      retained,
      ApiMethod.profilesUpdate,
      update('1', {'action': 'keep'}),
      'owned-a',
    );
    final b = submit(
      retained,
      ApiMethod.profilesUpdate,
      update('1', {'action': 'keep'}),
      'owned-b',
    );
    coordinator.detach('owned-a');
    await Future.wait([a, b]);
    check(store.state.profiles[fixture.profileId]!.revision == '2');
    await coordinator.close();

    // A controlled protection dependency delegates all successful calls to DPAPI.
    // It holds preparation before native commit to exercise running/queue races.
    final gate = GateProtection(custody.protection)
      ..reached = Completer<void>()
      ..release = Completer<void>();
    final gatedCustody = KeyCustody(gate, custody.ownerSid);
    coordinator = MutationCoordinator(store, gatedCustody, key);
    final runningId = request();
    final running = submit(
      runningId,
      ApiMethod.profilesUpdate,
      update('2', password),
    );
    await gate.reached!.future.timeout(const Duration(seconds: 5));
    check(coordinator.status(runningId).state == MutationState.running);
    coordinator.detach('owned-a');
    final queued = <Future<MutationResult>>[];
    for (var i = 0; i < 32; i++) {
      queued.add(
        submit(request(), ApiMethod.settingsUpdate, {
          'expectedRevision': (3 + i).toString(),
          'theme': 'dark',
          'reduceMotion': false,
          'selectedProfileId': null,
        }, 'owned-b'),
      );
    }
    await rejects(
      submit(request(), ApiMethod.settingsUpdate, {
        'expectedRevision': '3',
        'theme': 'dark',
        'reduceMotion': false,
        'selectedProfileId': null,
      }, 'owned-c'),
      'RESOURCE_LIMIT',
    );
    gate.release!.complete();
    await running;
    await Future.wait(queued);
    check(store.state.profiles[fixture.profileId]!.credentialRevision == '2');
    await coordinator.close();
    gate.reached = null;
    gate.release = null;
    gate.fail = true;
    coordinator = MutationCoordinator(store, gatedCustody, key);
    final failedId = request();
    final unchanged = store.state.storeRevision;
    await rejects(
      submit(failedId, ApiMethod.profilesUpdate, update('3', password)),
      'STORAGE_BLOCKED',
    );
    check(
      store.state.storeRevision == unchanged &&
          !store.state.receipts.containsKey(failedId),
    );
    var blocked = false;
    try {
      coordinator.status(failedId);
    } on StateError catch (error) {
      blocked = error.message == 'STORAGE_BLOCKED';
    }
    check(blocked);
    for (final read in <void Function()>[
      () {
        coordinator.listProfiles();
      },
      () {
        coordinator.getProfile(fixture.profileId);
      },
      () {
        coordinator.getSettings();
      },
      () {
        coordinator.recent();
      },
    ]) {
      var rejected = false;
      try {
        read();
      } on StateError catch (error) {
        rejected = error.message == 'STORAGE_BLOCKED';
      }
      check(rejected);
    }
    await coordinator.close();
    await store.close();
    store = null;
    store = await open();
    coordinator = MutationCoordinator(store, custody, key);
    check(coordinator.status(failedId).state == MutationState.notFound);
    await submit(failedId, ApiMethod.profilesUpdate, update('3', password));
    check(store.state.profiles[fixture.profileId]!.credentialRevision == '3');
    final sync = custody.receiptDigestSync(key, {
      'operation': 'profiles.create',
      'params': create,
    });
    check(
      sync ==
          await custody.receiptDigest(key, {
            'operation': 'profiles.create',
            'params': create,
          }),
    );
    await coordinator.close();
    var clock = DateTime.utc(2035);
    coordinator = MutationCoordinator(store, custody, key, clock: () => clock);
    const clockProfile = '72345678-1234-4234-8234-000000000001';
    await submit(request(), ApiMethod.profilesCreate, {
      ...create,
      'profileId': clockProfile,
    });
    clock = DateTime.utc(2020);
    await submit(request(), ApiMethod.profilesUpdate, {
      ...update('1', {'action': 'keep'}),
      'profileId': clockProfile,
    });
    check(
      store.state.profiles[clockProfile]!.toJson()['updatedAt'] ==
          '2035-01-01T00:00:00.000Z',
    );
    await coordinator.close();
    await store.close();
    store = null;
    store = await open();
    coordinator = MutationCoordinator(store, custody, key, clock: () => clock);
    await submit(request(), ApiMethod.settingsUpdate, {
      'expectedRevision': store.state.settings.revision,
      'theme': 'system',
      'reduceMotion': false,
      'selectedProfileId': null,
    });
    check(
      coordinator.recent(limit: 1).receipts.single.committedAt ==
          '2035-01-01T00:00:00.000Z',
    );
    validateMethodResult('mutations.recent', coordinator.recent().toJson());

    // Full revision matrix through the same durable coordinator, not fabricated
    // snapshots. Create with a credential starts all access revisions at one.
    const matrixId = 'b2345678-1234-4234-8234-000000000001';
    await submit(request(), ApiMethod.profilesCreate, {
      ...create,
      'profileId': matrixId,
      'credential': password,
    });
    final created = store.state.profiles[matrixId]!.toJson();
    final originalCredential =
        store.state.credentials[created['credentialRef']]!;
    check(originalCredential.revision == '1');
    var entityRevision = 1, connectionRevision = 1, accessRevision = 1;
    Map<String, Object?> matrixUpdate(Map<String, Object?> changes) {
      final current = store!.state.profiles[matrixId]!.toJson();
      return {
        'profileId': matrixId,
        'expectedRevision': current['revision'],
        for (final field in ['name', 'address', 'port', 'sshUser', 'tags'])
          field: current[field],
        'credential': {'action': 'keep'},
        ...changes,
      };
    }

    for (final (changes, connection, access)
        in <(Map<String, Object?>, bool, bool)>[
          (
            {
              'name': 'Matrix renamed',
              'tags': ['matrix'],
            },
            false,
            false,
          ),
          ({'address': 'other.invalid'}, true, false),
          ({'port': 2222}, true, false),
          ({'sshUser': 'other'}, true, false),
          ({}, false, false),
          (
            {
              'credential': {'action': 'remove'},
            },
            false,
            true,
          ),
          (
            {
              'credential': {'action': 'remove'},
            },
            false,
            true,
          ),
          ({'credential': password}, false, true),
          ({'credential': password}, false, true),
        ]) {
      final oldReference = store.state.profiles[matrixId]!.credentialRef;
      final result = await submit(
        request(),
        ApiMethod.profilesUpdate,
        matrixUpdate(changes),
      );
      entityRevision++;
      if (connection) connectionRevision++;
      if (access) accessRevision++;
      final current = store.state.profiles[matrixId]!.toJson();
      check(result.entityRevision == '$entityRevision');
      check(current['connectionRevision'] == '$connectionRevision');
      check(current['trustRevision'] == '$connectionRevision');
      check(current['credentialRevision'] == '$accessRevision');
      check(current['createdAt'] == created['createdAt']);
      final reference = current['credentialRef'] as String?;
      if (!access) {
        check(reference == originalCredential.id);
        check(
          store.state.credentials[reference]!.toJson().toString() ==
              originalCredential.toJson().toString(),
        );
      } else if ((changes['credential'] as Map)['action'] == 'remove') {
        check(reference == null);
      } else {
        check(reference != oldReference);
        final record = store.state.credentials[reference]!;
        check(record.revision == '$accessRevision');
        final fields = record.toJson();
        check(fields['createdAt'] == current['updatedAt']);
        check(fields['createdAt'] == fields['updatedAt']);
      }
      if (access && oldReference != null)
        check(!store.state.credentials.containsKey(oldReference));
    }
    // The coordinator owns a deep validated copy before its first async wait.
    final owned = matrixUpdate({
      'tags': <String>['owned'],
    });
    final ownedResult = submit(request(), ApiMethod.profilesUpdate, owned);
    (owned['tags'] as List).add('caller-change');
    owned['address'] = 'caller.invalid';
    await ownedResult;
    check(coordinator.getProfile(matrixId).profile.tags.single == 'owned');
    check(coordinator.getProfile(matrixId).profile.address == 'other.invalid');

    final sameRevision = matrixUpdate({'name': 'CAS winner'});
    final winner = submit(request(), ApiMethod.profilesUpdate, sameRevision);
    final loserId = request();
    final loser = rejects(
      submit(loserId, ApiMethod.profilesUpdate, {
        ...sameRevision,
        'name': 'CAS loser',
      }),
      'REVISION_CONFLICT',
    );
    await Future.wait([winner, loser]);
    check(coordinator.getProfile(matrixId).profile.name == 'CAS winner');
    check(coordinator.status(loserId).state == MutationState.notFound);
    final beforeSettings = store.state.storeRevision;
    final settingsInput = {
      'expectedRevision': store.state.settings.revision,
      'theme': 'light',
      'reduceMotion': true,
      'selectedProfileId': matrixId,
    };
    final settingsWinner = submit(
      request(),
      ApiMethod.settingsUpdate,
      settingsInput,
    );
    final settingsLoserId = request();
    final settingsLoser = rejects(
      submit(settingsLoserId, ApiMethod.settingsUpdate, {
        ...settingsInput,
        'theme': 'dark',
      }),
      'REVISION_CONFLICT',
    );
    await Future.wait([settingsWinner, settingsLoser]);
    check(
      store.state.storeRevision == (int.parse(beforeSettings) + 1).toString(),
    );
    check(coordinator.status(settingsLoserId).state == MutationState.notFound);
    final invalidSelection = request();
    final beforeMissing = store.state.storeRevision;
    await rejects(
      submit(invalidSelection, ApiMethod.settingsUpdate, {
        ...settingsInput,
        'expectedRevision': store.state.settings.revision,
        'selectedProfileId': 'b2345678-1234-4234-8234-000000000002',
      }),
      'NOT_FOUND',
    );
    check(store.state.storeRevision == beforeMissing);
    check(coordinator.status(invalidSelection).state == MutationState.notFound);
    String matrixSnapshot() => base64.encode(
      StrictCodec().canonical(store!.state.profiles[matrixId]!.toJson()),
    );
    final durableMatrix = matrixSnapshot();
    await coordinator.close();
    await store.close();
    store = null;
    store = await open();
    coordinator = MutationCoordinator(store, custody, key);
    check(matrixSnapshot() == durableMatrix);
    check(coordinator.getSettings().settings.selectedProfileId == matrixId);
    stdout.writeln('MUTATION_REVISION_MATRIX_PASSED');
  } finally {
    await coordinator.close();
    await store?.close();
  }
}
