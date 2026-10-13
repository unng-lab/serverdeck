import 'dart:convert';

import 'package:serverdeck_locald/storage/models.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-8234-123456789abc';
const receiptKeyId = '12345678-1234-4234-8234-123456789abd';
const profileId = '12345678-1234-4234-8234-123456789abe';
const credentialId = '12345678-1234-4234-8234-123456789abf';
const requestId = '12345678-1234-4234-8234-123456789ab0';
const sid = 'S-1-5-21-1-2-3-1001';
const time = '2026-10-11T01:00:00.000Z';

WorkspaceState parse(Map<String, Object?> value) => WorkspaceState.fromJson(
  value,
  workspaceId: workspace,
  receiptKeyId: receiptKeyId,
  ownerSid: sid,
);
Map<String, Object?> empty() => WorkspaceState.empty(
  workspaceId: workspace,
  receiptKeyId: receiptKeyId,
  ownerSid: sid,
).toJson();
Map<String, Object?> profile({
  String? credential,
  String revision = '1',
  String credentialRevision = '1',
}) => {
  'id': profileId,
  'revision': revision,
  'name': 'Synthetic',
  'address': 'example.invalid',
  'port': 22,
  'sshUser': 'synthetic',
  'tags': <String>[],
  'credentialRef': credential,
  'credentialRevision': credentialRevision,
  'connectionRevision': '1',
  'trustRevision': '1',
  'createdAt': time,
  'updatedAt': time,
};
Map<String, Object?> receipt() => {
  'requestId': requestId,
  'inputDigest': base64.encode(List.filled(32, 0)),
  'operation': 'profiles.create',
  'profileId': profileId,
  'result': {
    'entityId': profileId,
    'entityRevision': '1',
    'storeRevision': '1',
    'deleted': false,
  },
  'committedAt': time,
};
Map<String, Object?> populated() => {
  ...empty(),
  'storeRevision': '1',
  'profiles': {profileId: profile()},
  'receipts': {requestId: receipt()},
};

void main() {
  test(
    'empty workspace RAM model has defaults and survives strict roundtrip',
    () {
      final state = parse(empty());
      expect(state.storeRevision, '0');
      expect(state.toJson()['settings'], {
        'revision': '1',
        'theme': 'system',
        'reduceMotion': false,
        'selectedProfileId': null,
      });
      expect(parse(state.toJson()).toJson(), state.toJson());
      expect(parse(populated()).storeRevision, '1');
    },
  );
  test(
    'schema/identity/unknown private fields reject without revealing input',
    () {
      expect(
        () => parse({...empty(), 'schemaVersion': 2}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'category',
            'INCOMPATIBLE',
          ),
        ),
      );
      for (final change in <Map<String, Object?>>[
        {'workspaceId': receiptKeyId},
        {'ownerSid': 'marker'},
        {'secret': 'marker'},
        {
          'profiles': {
            profileId: {...profile(), 'password': 'marker'},
          },
        },
        {
          'profiles': {
            profileId: {...profile(), 'name': ' Synthetic '},
          },
        },
      ]) {
        expect(
          () => parse({...empty(), ...change}),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'category',
              'STORAGE_BLOCKED',
            ),
          ),
        );
      }
    },
  );
  test(
    'credential owner/ref/revision and selected-profile references must agree',
    () {
      final credential = <String, Object?>{
        'id': credentialId,
        'revision': '1',
        'profileId': profileId,
        'kind': 'password',
        'protectedBlob': base64.encode([1, 2, 3]),
        'createdAt': time,
        'updatedAt': time,
      };
      final state = {
        ...populated(),
        'profiles': {profileId: profile(credential: credentialId)},
        'credentials': {credentialId: credential},
      };
      expect(parse(state).toJson(), state);
      for (final change in <Map<String, Object?>>[
        {'credentials': <String, Object?>{}},
        {
          'credentials': {
            credentialId: {...credential, 'revision': '2'},
          },
        },
        {
          'profiles': {profileId: profile()},
        },
        {
          'credentials': {
            credentialId: {...credential, 'profileId': receiptKeyId},
          },
        },
        {
          'settings': {
            'revision': '1',
            'theme': 'system',
            'reduceMotion': false,
            'selectedProfileId': receiptKeyId,
          },
        },
      ]) {
        expect(() => parse({...state, ...change}), throwsA(isA<StateError>()));
      }
    },
  );
  test('revision overflow is rejected before a state can wrap or change', () {
    expect(nextRevision('0'), '1');
    expect(nextRevision('9223372036854775806'), '9223372036854775807');
    expect(
      () => nextRevision('9223372036854775807'),
      throwsA(isA<StateError>()),
    );
  });
  test(
    'persisted original results reject impossible historical entity revisions',
    () {
      for (final operation in [
        'profiles.create',
        'profiles.update',
        'profiles.delete',
        'settings.update',
      ]) {
        final settings = operation == 'settings.update';
        final historical = {
          ...receipt(),
          'operation': operation,
          'profileId': settings ? null : profileId,
          'result': {
            'entityId': settings ? null : profileId,
            'entityRevision': '99',
            'storeRevision': '1',
            'deleted': operation == 'profiles.delete',
          },
        };
        expect(
          () => parse({
            ...populated(),
            'receipts': {requestId: historical},
          }),
          throwsA(isA<StateError>()),
        );
      }
      final create = {
        ...receipt(),
        'result': {
          'entityId': profileId,
          'entityRevision': '2',
          'storeRevision': '1',
          'deleted': false,
        },
      };
      expect(
        () => parse({
          ...populated(),
          'receipts': {requestId: create},
        }),
        throwsA(isA<StateError>()),
      );
      final settings = {
        ...empty(),
        'storeRevision': '1',
        'settings': {
          'revision': '2',
          'theme': 'dark',
          'reduceMotion': false,
          'selectedProfileId': null,
        },
        'receipts': {
          requestId: {
            ...receipt(),
            'operation': 'settings.update',
            'profileId': null,
            'result': {
              'entityId': null,
              'entityRevision': '2',
              'storeRevision': '1',
              'deleted': false,
            },
          },
        },
      };
      expect(parse(settings).settings.revision, '2');
      for (final operation in ['profiles.update', 'settings.update']) {
        final isSettings = operation == 'settings.update';
        expect(
          () => parse({
            ...populated(),
            'receipts': {
              requestId: {
                ...receipt(),
                'operation': operation,
                'profileId': isSettings ? null : profileId,
                'result': {
                  'entityId': isSettings ? null : profileId,
                  'entityRevision': '1',
                  'storeRevision': '1',
                  'deleted': false,
                },
              },
            },
          }),
          throwsA(isA<StateError>()),
        );
      }
      const deleteId = '12345678-1234-4234-8234-123456789ab1';
      expect(
        () => parse({
          ...empty(),
          'storeRevision': '2',
          'receipts': {
            requestId: receipt(),
            deleteId: {
              ...receipt(),
              'requestId': deleteId,
              'operation': 'profiles.delete',
              'result': {
                'entityId': profileId,
                'entityRevision': '2',
                'storeRevision': '2',
                'deleted': true,
              },
            },
          },
        }),
        throwsA(isA<StateError>()),
      );
    },
  );
  test(
    'read projection and exported JSON cannot mutate the protected RAM model',
    () {
      final state = parse(populated());
      final projection = state.profiles[profileId]!.view(null).toJson();
      expect(projection.containsKey('credentialRef'), isFalse);
      expect(projection.containsKey('protectedBlob'), isFalse);
      expect(
        () => (projection['tags'] as List).add('changed'),
        throwsUnsupportedError,
      );
      final exported = state.toJson();
      ((exported['profiles'] as Map)[profileId]['tags'] as List).add('changed');
      expect(state.profiles[profileId]!.view(null).tags, isEmpty);
      expect(() => state.profiles.clear(), throwsUnsupportedError);
    },
  );
  test('corrupt receipt identity/digest/revision and initial staging invariants fail closed', () {
    expect(parse(empty()).isInitialEmpty, isTrue);
    expect(parse(populated()).isInitialEmpty, isFalse);
    for (final change in <Map<String, Object?>>[
      {'storeRevision': '0'},
      {'receipts': <String, Object?>{}},
      {
        'receipts': {receiptKeyId: receipt()},
      },
      {
        'receipts': {
          requestId: {...receipt(), 'inputDigest': 'private-invalid-marker'},
        },
      },
      {
        'receipts': {
          requestId: {
            ...receipt(),
            'result': {
              'entityId': profileId,
              'entityRevision': '1',
              'storeRevision': '0',
              'deleted': false,
            },
          },
        },
      },
      {
        'profiles': {
          profileId: {...profile(), 'trustRevision': '2'},
        },
      },
    ]) {
      expect(
        () => parse({...populated(), ...change}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe code',
            'STORAGE_BLOCKED',
          ),
        ),
      );
    }
  });
}
