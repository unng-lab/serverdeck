import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/mutation_controller.dart';
import 'package:serverdeck/settings/settings_controller.dart';
import 'package:serverdeck_protocol/models.dart';

import 'profile_controller_test.dart' as fixture;
import 'mutation_controller_test.dart' show MutationClient, receipt;

ClientSnapshot settingsSnapshot({String revision = '2'}) {
  final old = fixture.snapshot(revision: revision);
  return ClientSnapshot(
    old.profiles,
    ApiReply(fixture.fixtureGeneration, {
      'storeRevision': revision,
      'settings': SettingsView(
        revision: revision,
        theme: ThemePreference.light,
      ).toJson(),
    }),
  );
}

void main() {
  late MutationClient client;
  late fixture.ModelBootstrap bootstrap;
  late ProfileController model;
  late SettingsController draft;
  setUp(() {
    client = MutationClient();
    bootstrap = fixture.ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(fixture.snapshot());
    draft = SettingsController(model: model);
  });
  tearDown(() async {
    draft.dispose();
    model.dispose();
    await bootstrap.close();
    await client.events.close();
    await client.readErrors.close();
  });

  test(
    'draft and captured CAS survive external snapshots; commit needs readback',
    () async {
      draft.edit(theme: ThemePreference.light, reduceMotion: false);
      draft.select(null);
      client.events.add(settingsSnapshot());
      expect(draft.revision, '1');
      client.send = () async =>
          ApiReply(fixture.fixtureGeneration, receipt('3'));
      await draft.save();
      expect(client.sent.single.method, ApiMethod.settingsUpdate);
      expect(draft.revision, '1');
      expect(draft.theme, ThemePreference.light);
      expect(draft.reduceMotion, false);
      expect(draft.selectedProfileId, isNull);
      expect(draft.mutation.state, MutationPresentation.committed);
      client.events.add(settingsSnapshot(revision: '3'));
      expect(draft.mutation.state, MutationPresentation.succeeded);
    },
  );

  test('CAS preserves draft until explicit reload and never resends', () async {
    draft.edit(theme: ThemePreference.system);
    client.send = () async =>
        throw const LocalApiException(ErrorCode.revisionConflict);
    await draft.save();
    client.events.add(settingsSnapshot());
    expect(draft.theme, ThemePreference.system);
    expect(draft.selectedProfileId, fixture.profileId);
    await draft.reload();
    expect(draft.theme, ThemePreference.light);
    expect(draft.revision, '2');
    expect(draft.selectedProfileId, isNull);
    expect(draft.mutation.state, MutationPresentation.idle);
    expect(client.sent, hasLength(1));
  });

  test(
    'lost reply freezes draft and uses the same intent for explicit retry',
    () async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      client.status = () async => ApiReply(fixture.fixtureGeneration, {
        'state': 'not-found',
        'result': null,
      });
      await draft.save();
      draft.edit(theme: ThemePreference.light);
      draft.select(null);
      expect(draft.theme, ThemePreference.dark);
      expect(draft.selectedProfileId, fixture.profileId);
      await draft.mutation.checkResult();
      await draft.mutation.retry();
      expect(identical(client.sent[0], client.sent[1]), isTrue);
      expect(identical(client.queried.single, client.sent.first), isTrue);
    },
  );

  test(
    'outside-ready save sends nothing; failed reload retains draft',
    () async {
      bootstrap.show(ReadinessState.unavailable);
      await draft.save();
      await draft.reload();
      expect(client.sent, isEmpty);
      expect(draft.revision, '1');
      expect(draft.readError, isNotNull);
    },
  );
}
