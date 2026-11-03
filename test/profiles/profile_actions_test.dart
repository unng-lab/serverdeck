import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/profile_controller.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  late ProfileController c;
  setUp(() {
    h = FeatureHarness();
    c = ProfileController(
      operations: h.operations,
      actor: h.actors.ui,
      newId: h.newId,
      poll: false,
    );
  });
  tearDown(() async {
    c.dispose();
    await h.dispose();
  });
  test('CRUD controller reads saved data, leaves credentials out of projections and confirms delete', () async {
    final secret = PasswordInput(' synthetic password ');
    try {
      expect(
        await c.create(
          ProfileDraft(
            displayName: 'Server',
            host: 'example.invalid',
            username: 'root',
            authentication: secret,
          ),
          h.newId(),
        ),
        isNull,
      );
    } finally {
      secret.dispose();
    }
    expect(c.items.single.displayName, 'Server');
    final id = c.items.single.profileId;
    await c.select(id);
    expect(c.details!.profile.hasCredential, isTrue);
    expect(
      c.details!.toJson().toString(),
      isNot(contains('synthetic password')),
    );
    expect(c.details!.connection.state, ConnectionState.disconnected);
    expect(h.sessions, isEmpty);
    expect(
      await c.update(
        c.details!.profile,
        const ProfilePatch(displayName: 'Renamed'),
        h.newId(),
      ),
      isNull,
    );
    expect(c.items.single.displayName, 'Renamed');
    expect(await c.delete(c.items.single, confirmed: false), isNotNull);
    expect(c.items, hasLength(1));
    expect(await c.delete(c.items.single, confirmed: true), isNull);
    expect(c.items, isEmpty);
    expect(c.selected, isNull);
  });
  test('validation identifies the field and failed changes preserve the previous profile', () async {
    final id = await h.create();
    await c.select(id);
    final old = c.details!.profile;
    final failure = await c.update(
      old,
      const ProfilePatch(host: 'https://not-a-host.invalid'),
      h.newId(),
    );
    expect(failure?.code, FailureCode.invalidArgument);
    expect(failure?.field, OperationField.host);
    expect(c.details!.profile.host, old.host);
    expect(c.details!.profile.revision, old.revision);
    expect(h.sessions, isEmpty);
  });
}
