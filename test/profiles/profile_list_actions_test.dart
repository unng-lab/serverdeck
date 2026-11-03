import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/actor.dart';
import 'package:serverdeck/domain/app_operations.dart';
import 'package:serverdeck/domain/models.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck/profiles/profile_view.dart';
import 'package:serverdeck/theme/brand_theme.dart';
import 'package:serverdeck/ui/deck_components.dart';

const epoch = '00000001-0000-4000-8000-000000000000',
    profileId = '00000002-0000-4000-8000-000000000000';

final class ListOperations extends Fake implements AppOperations {
  final profile = ProfileView(
    profileId: profileId,
    revision: 1,
    connectionRevision: 1,
    displayName: 'Fixture server',
    host: 'host.invalid',
    port: 22,
    username: 'root',
    authKind: AuthKind.password,
    hasCredential: true,
    endpointId: '0'.padLeft(64, '0'),
  );
  final trust = const TrustView(
    trustRevision: 1,
    observationRevision: 2,
    changed: true,
    acceptedFingerprint: 'SHA256:public-old',
    observedFingerprint: 'SHA256:public-new',
  );
  int connects = 0, gets = 0;
  OperationResult<T> ok<T extends PublicValue>(T value) =>
      OperationResult.success(
        value,
        const OperationMeta(dataRevision: 1, ownerEpoch: epoch),
      );
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) async => ok(ProfilesPage(items: [profile], snapshotRevision: 1));
  @override
  Future<OperationResult<TrustView>> getTrust(Actor actor, String id) async =>
      ok(trust);
  @override
  Future<OperationResult<ProfileDetails>> getProfile(
    Actor actor,
    String id,
  ) async {
    gets++;
    return ok(
      ProfileDetails(
        profile: profile,
        connection: const ConnectionView(state: ConnectionState.disconnected),
        trust: trust,
      ),
    );
  }

  @override
  Future<OperationResult<ConnectionView>> connect(
    Actor actor,
    String id, {
    required int expectedRevision,
  }) async {
    connects++;
    return const OperationResult.failure(
      OperationFailure(FailureCode.networkError),
    );
  }
}

void main() {
  testWidgets(
    'C07 receives profile data and warning; selecting reads details without connecting',
    (tester) async {
      final operations = ListOperations(), actor = ActorAuthority(epoch).ui;
      final c = ProfileController(
        operations: operations,
        actor: actor,
        newId: () => profileId,
        poll: false,
      );
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: BrandTheme.dark,
          home: Scaffold(
            body: ProfileViewPanel(controller: c, pickKey: () async => null),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = tester.widget<DeckListItem>(find.byType(DeckListItem));
      expect(row.title, 'Fixture server');
      expect(row.description, 'root@host.invalid:22');
      expect(row.selected, isFalse);
      expect(row.onTap, isNotNull);
      expect(find.text('Ключ сервера изменился'), findsOneWidget);
      expect(operations.connects, 0);
      await tester.tap(find.text('Fixture server'));
      await tester.pumpAndSettle();
      expect(c.selected, profileId);
      expect(c.details!.profile.profileId, profileId);
      expect(operations.gets, 1);
      expect(operations.connects, 0);
      expect(
        tester.widget<DeckListItem>(find.byType(DeckListItem)).selected,
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
