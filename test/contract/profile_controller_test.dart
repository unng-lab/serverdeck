import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/bootstrap_controller.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck_protocol/models.dart';

const fixtureGeneration = '11111111-1111-4111-8111-111111111111';
const profileId = '22222222-2222-4222-8222-222222222222';

class ModelClient extends LocalApiClient {
  ModelClient() : super(connect: () => throw StateError('UNUSED'));
  final events = StreamController<ClientSnapshot>.broadcast(sync: true);
  final readErrors = StreamController<ErrorCode>.broadcast(sync: true);
  @override
  Stream<ErrorCode> get snapshotErrors => readErrors.stream;
  int refreshes = 0;
  @override
  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method == ApiMethod.mutationsRecent)
      return ApiReply(generationId, {
        'receipts': <Object?>[],
        'truncated': false,
      });
    return super.read(method, params);
  }

  Completer<void>? refreshGate;
  @override
  String? get generation => generationId;
  String generationId = fixtureGeneration;
  @override
  Stream<ClientSnapshot> get snapshots => events.stream;
  @override
  Future<void> refreshSnapshot() async {
    refreshes++;
    await refreshGate?.future;
  }
}

class ModelBootstrap extends BootstrapController {
  ModelBootstrap(ModelClient client)
    : super(client: client, prepare: () async {}, ensureService: () async {});
  ReadinessState value = ReadinessState.unavailable;
  int epoch = 0;
  @override
  int get readinessEpoch => epoch;
  @override
  ReadinessState get state => value;
  void show(ReadinessState next) {
    if (next != value) epoch++;
    value = next;
    notifyListeners();
  }
}

ClientSnapshot snapshot({
  String revision = '1',
  String gen = fixtureGeneration,
}) => ClientSnapshot(
  ApiReply(gen, {
    'storeRevision': revision,
    'profiles': [
      const ProfileView(
        id: profileId,
        revision: '1',
        name: 'Saved profile',
        address: '192.0.2.1',
        port: 22,
        sshUser: 'admin',
        tags: ['production'],
        credentialRevision: '1',
        connectionRevision: '1',
        trustRevision: '1',
        createdAt: '2026-10-11T00:00:00.000Z',
        updatedAt: '2026-10-11T00:00:00.000Z',
        credentialKind: CredentialKind.password,
        credentialConfigured: true,
      ).toJson(),
    ],
  }),
  ApiReply(gen, {
    'storeRevision': revision,
    'settings': const SettingsView(
      theme: ThemePreference.dark,
      reduceMotion: true,
      selectedProfileId: profileId,
    ).toJson(),
  }),
);

void main() {
  test(
    'new ready consumer does not relabel a joined retired refresh failure',
    () async {
      final client = ModelClient()..refreshGate = Completer<void>();
      final owner = ModelBootstrap(client)..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: owner);
      owner.show(ReadinessState.unavailable);
      owner.show(ReadinessState.ready);
      client.refreshGate!.completeError(
        const LocalApiException(ErrorCode.storageBlocked),
      );
      await Future<void>.delayed(Duration.zero);
      expect(model.error, isNull);
      expect(model.loaded, isFalse);
      client.events.add(snapshot());
      expect(model.loaded, isTrue);
      expect(model.selected!.id, profileId);
      model.dispose();
      await client.events.close();
      await client.readErrors.close();
      await owner.close();
    },
  );
  test(
    'ready gates model reads and removes retained private state on failure',
    () async {
      final client = ModelClient();
      final owner = ModelBootstrap(client);
      final model = ProfileController(bootstrap: owner);
      client.events.add(snapshot());
      expect(model.loaded, isFalse);
      expect(model.profiles, isEmpty);
      expect(client.refreshes, 0);
      owner.show(ReadinessState.ready);
      await Future<void>.delayed(Duration.zero);
      expect(client.refreshes, 1);
      client.events.add(snapshot());
      expect(model.loaded, isTrue);
      expect(model.selected!.id, profileId);
      expect(model.settings!.theme, ThemePreference.dark);
      owner.show(ReadinessState.storageBlocked);
      expect(model.loaded, isFalse);
      expect(model.profiles, isEmpty);
      expect(model.selected, isNull);
      expect(model.settings, isNull);
      client.events.add(snapshot(revision: '2'));
      expect(model.loaded, isFalse);
      owner.show(ReadinessState.ready);
      client.events.add(snapshot());
      expect(model.loaded, isTrue);
      expect(model.selected!.id, profileId);
      expect(model.settings!.theme, ThemePreference.dark);
      client.readErrors.add(ErrorCode.timeout);
      expect(model.loaded, isFalse);
      expect(model.error, ErrorCode.timeout);
      expect(model.selected, isNull);
      client.events.add(snapshot());
      expect(model.loaded, isTrue);
      expect(model.error, isNull);
      owner.show(ReadinessState.unavailable);
      client.readErrors.add(ErrorCode.timeout);
      expect(model.error, isNull);
      model.dispose();
      await client.events.close();
      await client.readErrors.close();
      await owner.close();
    },
  );

  test(
    'coherent monotonic snapshots only; invalid replies have safe errors',
    () async {
      final client = ModelClient();
      final owner = ModelBootstrap(client)..show(ReadinessState.ready);
      final model = ProfileController(bootstrap: owner);
      client.events.add(snapshot(revision: '2'));
      client.events.add(snapshot(revision: '1'));
      client.events.add(snapshot(revision: '3', gen: profileId));
      expect(model.storeRevision, '2');
      final valid = snapshot(revision: '3');
      client.events.add(
        ClientSnapshot(valid.profiles, snapshot(revision: '4').settings),
      );
      expect(model.storeRevision, '2');
      client.events.add(
        ClientSnapshot(
          ApiReply(fixtureGeneration, {
            'storeRevision': '3',
            'profiles': 'private malformed source',
          }),
          valid.settings,
        ),
      );
      expect(model.error, ErrorCode.incompatible);
      expect(model.loaded, isFalse);
      expect(model.profiles, isEmpty);
      client.events.add(snapshot(revision: '4'));
      expect(model.loaded, isTrue);
      expect(model.error, isNull);
      model.dispose();
      await client.events.close();
      await client.readErrors.close();
      await owner.close();
    },
  );
}
