import 'package:serverdeck_protocol/automation/models.dart';
import 'package:test/test.dart';

Map<String, Object?> motdBody() => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': {
    'message': {'type': 'string', 'maxLength': 4096, 'default': 'Hello\n'},
  },
  'steps': [
    {
      'id': 'welcome',
      'kind': 'config_file',
      'resourceId': 'system.motd',
      'values': {
        'text': {'param': 'message'},
      },
    },
  ],
};

void main() {
  test(
    'C1 controls are rejected in defaults, literals and parameter overrides',
    () {
      for (final codepoint in [0x7f, 0x80, 0x85, 0x9f]) {
        final text = 'Hello${String.fromCharCode(codepoint)}World';
        final defaults = motdBody();
        ((defaults['parameters'] as Map)['message'] as Map)['default'] = text;
        expect(() => AutomationBody.fromJson(defaults), throwsFormatException);
        final literal = motdBody();
        ((literal['steps'] as List).single as Map)['values'] =
            <String, Object?>{'text': text};
        expect(() => AutomationBody.fromJson(literal), throwsFormatException);
        expect(
          () =>
              AutomationBody.fromJson(motdBody())
                  .resolveParameters({'message': text}),
          throwsFormatException,
        );
      }
      for (final codepoint in [0x7e, 0xa0, 9, 10]) {
        final text = 'Hello${String.fromCharCode(codepoint)}World';
        expect(
          AutomationBody.fromJson(motdBody())
              .resolveParameters({'message': text}),
          {'message': text},
        );
      }
    },
  );

  test(
    'revision load verifies digest, parent chain and immutable exact identity',
    () async {
      const id = '10000000-0000-4000-8000-000000000001';
      final body = AutomationBody.fromJson(motdBody());
      final value = <String, Object?>{
        'workspaceId': id,
        'profileId': id,
        'revision': 1,
        'parentRevision': null,
        'bodyFormat': 1,
        'body': body.toJson(),
        'digest': await body.digest(),
        'authorGrantId': null,
        'createdAt': '2026-10-21T10:00:00.000Z',
      };
      final pending = AutomationRevisionRecord.fromJson(value);
      (value['body'] as Map)['steps'] = [];
      final first = await pending;
      expect(first.body.resolveSteps({}), hasLength(1));
      final next = await AutomationRevisionRecord.fromJson({
        ...first.toJson(),
        'revision': 2,
        'parentRevision': 1,
      });
      expect(first.key, isNot(next.key));
      expect(first.key.bodyDigest, next.key.bodyDigest);
      expect(next.toJson()['parentRevision'], 1);
      for (final patch in <Map<String, Object?>>[
        {'digest': List.filled(64, 'a').join()},
        {'parentRevision': 1},
        {'revision': 3, 'parentRevision': 1},
        {'bodyFormat': 2},
        {'createdAt': '2026-10-21T10:00:00Z'},
        {'authorGrantId': 'invalid'},
      ]) {
        await expectLater(
          AutomationRevisionRecord.fromJson({...first.toJson(), ...patch}),
          throwsFormatException,
        );
      }
    },
  );

  test('profile metadata has exact bounded non-executable fields', () {
    const id = '10000000-0000-4000-8000-000000000001';
    final value = <String, Object?>{
      'workspaceId': id,
      'id': id,
      'name': '{{display only}}',
      'description': 'Line1\nLine2',
      'headRevision': 1,
      'archived': false,
    };
    final profile = AutomationProfileRecord.fromJson(value);
    expect(profile.toJson(), value);
    for (final patch in <Map<String, Object?>>[
      {'name': ''},
      {'archived': 'false'},
      {'headRevision': 0},
      {'extra': true},
      {'description': List.filled(2001, 'a').join()},
    ]) {
      expect(
        () => AutomationProfileRecord.fromJson({...value, ...patch}),
        throwsFormatException,
      );
    }
  });

  test('defaults and explicit values resolve once without caller mutation', () {
    final input = motdBody();
    final body = AutomationBody.fromJson(input);
    expect(body.resolveParameters({}), {'message': 'Hello\n'});
    expect(body.resolveSteps({'message': 'Updated\t🙂'}).single, {
      'id': 'welcome',
      'kind': 'config_file',
      'resourceId': 'system.motd',
      'values': {'text': 'Updated\t🙂'},
    });
    (input['steps'] as List).clear();
    (body.toJson()['steps'] as List).clear();
    expect(body.resolveSteps({}), hasLength(1));
    expect(
      () => body.resolveParameters({'unknown': true}),
      throwsFormatException,
    );
    expect(() => body.resolveParameters({'message': 1}), throwsFormatException);
  });

  test('executable strings reject templates, controls and private fields', () {
    for (final value in [
      '{{secret}}',
      '{% x %}',
      '{#comment#}',
      'a\u0000',
      'a\r',
    ]) {
      expect(
        () =>
            AutomationBody.fromJson(motdBody())
                .resolveParameters({'message': value}),
        throwsFormatException,
      );
      final input = motdBody();
      ((input['parameters'] as Map)['message'] as Map)['default'] = value;
      expect(() => AutomationBody.fromJson(input), throwsFormatException);
    }
    expect(
      () => AutomationBody.fromJson({...motdBody(), 'privateKey': 'marker'}),
      throwsFormatException,
    );
  });

  test(
    'resource ranges apply to literals and all possible reference values',
    () {
      Map<String, Object?> body(
        Object? memory, {
        Map<String, Object?> params = const {},
      }) => {
        'format': 1,
        'environment': 'ubuntu24.04-amd64-systemd',
        'parameters': params,
        'steps': [
          {
            'id': 'settings',
            'kind': 'config_file',
            'resourceId': 'clickhouse.settings',
            'values': {
              'max_connections': 100,
              'max_server_memory_usage_mb': memory,
            },
          },
        ],
      };
      expect(
        AutomationBody.fromJson(body(1048576)).resolveSteps({}),
        hasLength(1),
      );
      for (final invalid in [127, 1048577, 128.0, '128', true]) {
        expect(
          () => AutomationBody.fromJson(body(invalid)),
          throwsFormatException,
        );
      }
      expect(
        () => AutomationBody.fromJson(
          body(
            {'param': 'memory'},
            params: {
              'memory': {
                'type': 'integer',
                'minimum': 0,
                'maximum': 1000,
                'default': 128,
              },
            },
          ),
        ),
        throwsFormatException,
      );
      expect(
        AutomationBody.fromJson(
          body(
            {'param': 'memory'},
            params: {
              'memory': {
                'type': 'integer',
                'minimum': 128,
                'maximum': 1000,
                'default': 128,
              },
            },
          ),
        ).resolveSteps({'memory': 1000}),
        hasLength(1),
      );
    },
  );

  test('unknown resources, duplicate effects, missing refs and extra step fields fail closed', () {
    for (final step in <Map<String, Object?>>[
      {'id': 'x', 'kind': 'shell', 'command': 'true'},
      {
        'id': 'x',
        'kind': 'service',
        'resourceId': 'netbird.service',
        'state': 'stopped',
      },
      {
        'id': 'x',
        'kind': 'service',
        'resourceId': 'postgresql.service',
        'state': {'param': 'missing'},
      },
      {
        'id': 'x',
        'kind': 'service',
        'resourceId': 'postgresql.service',
        'state': 'started',
        'force': true,
      },
      {
        'id': 'x',
        'kind': 'config_file',
        'resourceId': 'postgresql.settings',
        'values': {'max_connections': 100},
      },
    ]) {
      expect(
        () => AutomationBody.fromJson({
          ...motdBody(),
          'steps': [step],
        }),
        throwsFormatException,
      );
    }
    final step = (motdBody()['steps'] as List).single as Map<String, Object?>;
    expect(
      () => AutomationBody.fromJson({
        ...motdBody(),
        'steps': [
          step,
          {...step, 'id': 'other'},
        ],
      }),
      throwsFormatException,
    );
  });

  test(
    'parameter unions reject coercion, invalid defaults and unbounded states',
    () {
      for (final definition in <Map<String, Object?>>[
        {'type': 'boolean', 'default': 1},
        {'type': 'integer', 'minimum': 1, 'maximum': 1000001, 'default': 1},
        {'type': 'integer', 'minimum': 2, 'maximum': 1, 'default': 1},
        {
          'type': 'enum',
          'values': ['a', 'a'],
          'default': 'a',
        },
        {
          'type': 'enum',
          'values': ['a'],
          'default': 'b',
        },
        {'type': 'string', 'maxLength': 1, 'default': 'ab'},
        {'type': 'secret', 'default': 'marker'},
      ]) {
        expect(
          () => AutomationBody.fromJson({
            ...motdBody(),
            'parameters': {'message': definition},
          }),
          throwsFormatException,
        );
      }
      expect(
        () => AutomationBody.fromJson({
          ...motdBody(),
          'parameters': {
            'state': {'type': 'string', 'maxLength': 20, 'default': 'started'},
          },
          'steps': [
            {
              'id': 'db',
              'kind': 'service',
              'resourceId': 'postgresql.service',
              'state': {'param': 'state'},
            },
          ],
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'canonical digest is order independent and snapshot is immutable',
    () async {
      final original = AutomationBody.fromJson(motdBody());
      final reordered = AutomationBody.fromJson(
        Map.fromEntries(motdBody().entries.toList().reversed),
      );
      expect(await original.digest(), await reordered.digest());
      final changed = motdBody();
      ((changed['parameters'] as Map)['message'] as Map)['default'] = 'Other';
      expect(
        await original.digest(),
        isNot(await AutomationBody.fromJson(changed).digest()),
      );
    },
  );

  test(
    'body cardinality, UTF8 size and Unicode codepoint limits are bounded',
    () {
      final input = motdBody();
      ((input['parameters'] as Map)['message'] as Map)['default'] = List.filled(
        4096,
        '🙂',
      ).join();
      expect(AutomationBody.fromJson(input).resolveParameters({}), isNotEmpty);
      final oversized = {
        ...motdBody(),
        'steps': List.filled(33, (motdBody()['steps'] as List).single),
      };
      expect(() => AutomationBody.fromJson(oversized), throwsFormatException);
      final parameters = <String, Object?>{};
      for (var i = 0; i < 32; i++) {
        parameters['p$i'] = {
          'type': 'string',
          'maxLength': 4096,
          'default': List.filled(4096, '🙂').join(),
        };
      }
      expect(
        () =>
            AutomationBody.fromJson({...motdBody(), 'parameters': parameters}),
        throwsFormatException,
      );
    },
  );
}
