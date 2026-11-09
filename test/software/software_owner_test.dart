import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/receipt_book.dart';
import 'package:serverdeck/software/software_models.dart';
import 'package:serverdeck/software/software_owner.dart';
import 'package:serverdeck/storage/records.dart';

import '../fixtures/feature_harness.dart';

final class ProbeState implements OperationState {
  ProbeState(this.source, this.onAuthorization);
  final OperationState source;
  final void Function(AuthorizationPoint) onAuthorization;
  @override
  String get ownerEpoch => source.ownerEpoch;
  @override
  bool get running => source.running;
  @override
  int get dataRevision => source.dataRevision;
  @override
  EntityVersions? versions(String id) => source.versions(id);
  @override
  bool isAuthorizedNow(CommandActor actor) => source.isAuthorizedNow(actor);
  @override
  Future<void> authorize(CommandActor actor, AuthorizationPoint point) async {
    await source.authorize(actor, point);
    onAuthorization(point);
  }
}

void main() {
  late FeatureHarness h;
  late SoftwareOwner owner;
  late String profile;
  SoftwareCardInput input([String name = 'Redis']) => SoftwareCardInput(
    name: name,
    version: null,
    service: 'redis-server',
    dataPaths: ['/var/lib/redis'],
    configPaths: [],
  );
  setUp(() async {
    h = FeatureHarness();
    profile = await h.create();
    owner = SoftwareOwner(
      gate: h.gate,
      repository: h.repository,
      receipts: ReceiptBook(h.signer, h.clock.now),
      newId: h.newId,
      utcNow: h.clock.now,
    );
  });
  tearDown(() async {
    await owner.dispose();
    await h.dispose();
  });
  test('same owner CRUD preserves fields and events; stale changes cannot overwrite', () async {
    final saved = await owner.save(
      h.actors.ui,
      profile,
      input(),
      mutationId: h.newId(),
    );
    expect(saved.ok, true);
    final id = saved.value!.entityId;
    final read = await owner.get(h.actors.ui, id);
    expect(
      (read.value!.software as SoftwareCardView).card.toJson(),
      input().toJson(),
    );
    final updated = await owner.save(
      h.actors.ui,
      profile,
      input('Redis 2'),
      softwareId: id,
      expectedRevision: 1,
      mutationId: h.newId(),
    );
    expect(updated.value!.revision, 2);
    expect(
      (await owner.delete(
        h.actors.ui,
        profile,
        id,
        expectedRevision: 1,
        mutationId: h.newId(),
      )).error?.code,
      FailureCode.conflict,
    );
    expect(h.repository.state.softwareEvents.length, 2);
    expect(
      (await owner.delete(
        h.actors.ui,
        profile,
        id,
        expectedRevision: 2,
        mutationId: h.newId(),
      )).ok,
      true,
    );
    expect(h.repository.state.softwareCards, isEmpty);
    expect(h.repository.state.softwareEvents.length, 3);
  });
  test(
    'committed save replays after profile cascade without resurrection',
    () async {
      final mutation = h.newId();
      final saved = await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: mutation,
      );
      await h.repository.write((r) => r.deleteProfile(profile));
      final replay = await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: mutation,
      );
      expect(replay.value!.replayed, true);
      expect(replay.value!.entityId, saved.value!.entityId);
      expect(h.repository.state.softwareCards, isEmpty);
      expect(h.repository.state.softwareEvents, isEmpty);
    },
  );
  test(
    'pagination is stable until revision changes and rejects wrong filter',
    () async {
      for (var i = 0; i < 3; i++) {
        expect(
          (await owner.save(
            h.actors.ui,
            profile,
            input('Redis $i'),
            mutationId: h.newId(),
          )).ok,
          true,
        );
      }
      final first =
          (await owner.list(h.actors.ui, profile, limit: 2)).value!.software
              as SoftwarePage;
      expect(first.items.length, 2);
      expect(first.nextCursor, isNotNull);
      final second =
          (await owner.list(
                h.actors.ui,
                profile,
                limit: 2,
                cursor: first.nextCursor,
              )).value!.software
              as SoftwarePage;
      expect(second.items.length, 1);
      expect(second.nextCursor, isNull);
      expect((second.items.single as SoftwareCardView).card.name, 'Redis 2');
      final other = await h.create();
      expect(
        (await owner.list(
          h.actors.ui,
          other,
          cursor: first.nextCursor,
        )).error?.code,
        FailureCode.invalidArgument,
      );
      expect(
        (await owner.list(
          h.actors.ui,
          profile,
          cursor: first.nextCursor,
        )).error?.code,
        FailureCode.conflict,
      );
      for (final cursor in ['', 'not canonical']) {
        expect(
          (await owner.list(h.actors.ui, profile, cursor: cursor)).error?.code,
          FailureCode.invalidArgument,
        );
      }
    },
  );
  test(
    'changed endpoint is visible; stale target cannot update but can delete',
    () async {
      final id = (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).value!.entityId;
      await h.repository.write((r) {
        r.putProfile(r.profile(profile)!..endpointId = 'changed');
      });
      expect(
        ((await owner.get(h.actors.ui, id)).value!.software as SoftwareCardView)
            .currentTarget,
        false,
      );
      expect(
        (await owner.save(
          h.actors.ui,
          profile,
          input('new'),
          softwareId: id,
          expectedRevision: 1,
          mutationId: h.newId(),
        )).error?.code,
        FailureCode.conflict,
      );
      expect(
        (await owner.delete(
          h.actors.ui,
          profile,
          id,
          expectedRevision: 1,
          mutationId: h.newId(),
        )).ok,
        true,
      );
    },
  );
  test('concurrent same mutation has one effect; exact original spelling is signed', () async {
    final mutation = h.newId();
    final results = await Future.wait(
      List.generate(
        2,
        (_) => owner.save(
          h.actors.ui,
          profile,
          input(' Redis '),
          mutationId: mutation,
        ),
      ),
    );
    expect(results.every((r) => r.ok), true);
    expect(results.map((r) => r.value!.entityId).toSet().length, 1);
    expect(h.repository.state.softwareCards.length, 1);
    expect(h.repository.state.softwareEvents.length, 1);
    expect(
      (await owner.save(
        h.actors.ui,
        profile,
        input('Redis'),
        mutationId: mutation,
      )).error?.code,
      FailureCode.conflict,
    );
    final id = results.first.value!.entityId;
    final deletion = h.newId();
    await owner.delete(
      h.actors.ui,
      profile,
      id,
      expectedRevision: 1,
      mutationId: deletion,
    );
    await h.repository.write((r) => r.deleteProfile(profile));
    expect(
      (await owner.delete(
        h.actors.ui,
        profile,
        id,
        expectedRevision: 1,
        mutationId: deletion,
      )).value!.replayed,
      true,
    );
  });
  test(
    'MCP revoke blocks replay and cannot forge the recorded author',
    () async {
      final grant = await h.grants.issue(h.actors.ui, 'AI', confirmed: true);
      await h.grants.setEnabled(h.actors.ui, true);
      final actor = h.actors.mcp(clientId: grant.clientId, grantVersion: 1);
      final mutation = h.newId();
      final saved = await owner.save(
        actor,
        profile,
        input(),
        mutationId: mutation,
      );
      expect(saved.ok, true);
      expect(
        h.repository.state.softwareEvents.values.single.clientId,
        grant.clientId,
      );
      await h.grants.revoke(h.actors.ui, grant.clientId, confirmed: true);
      expect(
        (await owner.save(actor, profile, input(), mutationId: mutation)).ok,
        false,
      );
      expect(h.repository.state.softwareCards.length, 1);
    },
  );
  test('profile card quota rejects new effects without evicting cards or adding history', () async {
    await h.repository.write((r) {
      for (var i = 0; i < 1000; i++) {
        r.putSoftwareCard(
          SoftwareCardRecord()
            ..softwareId = featureId(10000 + i)
            ..profileId = profile
            ..name = 'Seed',
        );
      }
    });
    expect(
      (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).error?.code,
      FailureCode.resourceExhausted,
    );
    expect(h.repository.state.softwareCards.length, 1000);
    expect(h.repository.state.softwareEvents, isEmpty);
  });
  test(
    'notes preserve reported outcome, metadata and deleted-card history',
    () async {
      final id = (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).value!.entityId;
      final mutation = h.newId();
      final note = SoftwareNoteInput(
        action: 'configure',
        summary: 'Конфиг изменён',
        outcome: 'unknown',
      );
      final added = await owner.addNote(
        h.actors.ui,
        profile,
        note,
        softwareId: id,
        mutationId: mutation,
      );
      expect(added.ok, true);
      expect(added.value!.revision, 1);
      expect(
        (await owner.addNote(
          h.actors.ui,
          profile,
          note,
          softwareId: id,
          mutationId: mutation,
        )).value!.replayed,
        true,
      );
      await owner.delete(
        h.actors.ui,
        profile,
        id,
        expectedRevision: 1,
        mutationId: h.newId(),
      );
      final page =
          (await owner.history(
                h.actors.ui,
                profile,
                softwareId: id,
              )).value!.software
              as SoftwarePage;
      expect(page.items.length, 3);
      final saved = page.items.whereType<SoftwareEventView>().singleWhere(
        (e) => e.kind == 'note',
      );
      expect(saved.softwareName, 'Redis');
      expect(saved.outcome, 'unknown');
      expect(saved.actorKind, 'ui');
      expect(saved.clientId, isNull);
      expect(saved.createdAt, h.clock.utc);
      expect(saved.toJson().keys, isNot(contains('output')));
      await h.repository.write((r) => r.deleteProfile(profile));
      expect(
        (await owner.addNote(
          h.actors.ui,
          profile,
          note,
          softwareId: id,
          mutationId: mutation,
        )).value!.replayed,
        true,
      );
      expect(h.repository.state.softwareEvents, isEmpty);
    },
  );
  test(
    'new notes require current card target; profile note captures current host',
    () async {
      final id = (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).value!.entityId;
      await h.repository.write(
        (r) => r.putProfile(
          r.profile(profile)!
            ..endpointId = 'new-target'
            ..normalizedHost = 'new.invalid',
        ),
      );
      final note = SoftwareNoteInput(
        action: 'analyze',
        summary: 'Обследовано',
        outcome: 'success',
      );
      expect(
        (await owner.addNote(
          h.actors.ui,
          profile,
          note,
          softwareId: id,
          mutationId: h.newId(),
        )).error?.code,
        FailureCode.conflict,
      );
      expect(
        (await owner.addNote(
          h.actors.ui,
          profile,
          note,
          mutationId: h.newId(),
        )).ok,
        true,
      );
      final events =
          (await owner.history(h.actors.ui, profile)).value!.software
              as SoftwarePage;
      expect(
        events.items
            .whereType<SoftwareEventView>()
            .singleWhere((e) => e.kind == 'note')
            .host,
        'new.invalid',
      );
    },
  );
  test('note rollback and global last10000 retention are atomic', () async {
    final note = SoftwareNoteInput(
      action: 'status',
      summary: 'Observed',
      outcome: 'unknown',
    );
    h.repository.failCommit = true;
    expect(
      (await owner.addNote(
        h.actors.ui,
        profile,
        note,
        mutationId: h.newId(),
      )).error?.code,
      FailureCode.storageUnavailable,
    );
    expect(h.repository.state.softwareEvents, isEmpty);
    await h.repository.write((r) {
      for (var i = 0; i < 10000; i++) {
        r.putSoftwareEvent(
          SoftwareEventRecord()
            ..eventId = featureId(100000 + i)
            ..profileId = profile
            ..kind = 'deleted'
            ..summary = 'deleted'
            ..createdAt = i,
        );
      }
    });
    expect(
      (await owner.addNote(
        h.actors.ui,
        profile,
        note,
        mutationId: h.newId(),
      )).ok,
      true,
    );
    expect(h.repository.state.softwareEvents.length, 10000);
    expect(
      h.repository.state.softwareEvents.containsKey(featureId(100000)),
      false,
    );
  });
  for (final stage in ['commit', 'response']) {
    test(
      'revoke at $stage prevents unauthorized data; committed effect is retained',
      () async {
        final grant = await h.grants.issue(h.actors.ui, 'AI', confirmed: true);
        await h.grants.setEnabled(h.actors.ui, true);
        final actor = h.actors.mcp(clientId: grant.clientId, grantVersion: 1);
        void revoke() =>
            h.repository.state.grants[grant.clientId]!.revokedAt = h.clock.utc;
        await owner.dispose();
        owner = SoftwareOwner(
          gate: DomainCommandGate(
            actors: h.actors,
            state: ProbeState(h.state, (point) {
              if (stage == 'commit' && point == AuthorizationPoint.admission) {
                h.repository.beforeWrite = () async {
                  revoke();
                  h.repository.beforeWrite = null;
                };
              }
              if (stage == 'response' && point == AuthorizationPoint.response)
                revoke();
            }),
          ),
          repository: h.repository,
          receipts: ReceiptBook(h.signer, h.clock.now),
          newId: h.newId,
          utcNow: h.clock.now,
        );
        final result = await owner.save(
          actor,
          profile,
          input(),
          mutationId: h.newId(),
        );
        expect(result.ok, false);
        expect(result.value, isNull);
        expect(
          h.repository.state.softwareCards.length,
          stage == 'commit' ? 0 : 1,
        );
        expect(
          h.repository.state.softwareEvents.length,
          stage == 'commit' ? 0 : 1,
        );
      },
    );
  }
  test(
    'duplicate names and no-op saves are separate records and revisions',
    () async {
      final one = (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).value!;
      final two = (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).value!;
      expect(one.entityId, isNot(two.entityId));
      expect(
        (await owner.save(
          h.actors.ui,
          profile,
          input(),
          softwareId: one.entityId,
          expectedRevision: 1,
          mutationId: h.newId(),
        )).value!.revision,
        2,
      );
    },
  );
  test('failed commit leaves no card, event, receipt or revision', () async {
    final before = h.repository.state.settings.dataRevision;
    final receipts = h.repository.state.receipts.length;
    h.repository.failCommit = true;
    expect(
      (await owner.save(
        h.actors.ui,
        profile,
        input(),
        mutationId: h.newId(),
      )).error?.code,
      FailureCode.storageUnavailable,
    );
    expect(h.repository.state.softwareCards, isEmpty);
    expect(h.repository.state.softwareEvents, isEmpty);
    expect(h.repository.state.receipts.length, receipts);
    expect(h.repository.state.settings.dataRevision, before);
  });
}
