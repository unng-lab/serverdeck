import 'package:serverdeck_engine/automation/compiler.dart';
import 'package:serverdeck_engine/automation/profile_diff.dart';
import 'package:serverdeck_protocol/automation/profile_body.dart';
import 'package:test/test.dart';

Map<String, Object?> motdBody() => {
  'format': 1,
  'environment': 'ubuntu24.04-amd64-systemd',
  'parameters': {
    'message': {'type': 'string', 'maxLength': 64, 'default': 'default'},
  },
  'steps': [
    {
      'id': 'motd',
      'kind': 'config_file',
      'resourceId': 'system.motd',
      'values': {
        'text': {'param': 'message'},
      },
    },
  ],
};

Matcher safeState(String code) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

void main() {
  test(
    'compiler retains typed intent and captures immutable program snapshots',
    () {
      final input = motdBody();
      final body = AutomationBody.fromJson(input);
      (input['steps'] as List).clear();
      final result = compileAutomation(
        body: body,
        parameters: {'message': 'unit message\n\n'},
        baselineFingerprints: {'system.motd': 'a' * 64},
        qualifiedRecipes: {},
      );
      final value = result.toJson();
      expect(value['parameters'], {'message': 'unit message\n\n'});
      final effects = value['effects'] as List;
      expect(effects, hasLength(1));
      expect(effects.single, containsPair('kind', 'config_file'));
      expect(effects.single, containsPair('resourceId', 'system.motd'));
      expect(
        renderedConfiguration('system.motd', {'text': 'unit message\n\n'}),
        'unit message\n',
      );
      expect(value['checks'], [
        {
          'id': 'c1',
          'effectId': 'e1',
          'resourceId': 'system.motd',
          'kind': 'file_digest',
          'digest': (effects.single as Map)['renderedDigest'],
        },
      ]);
      effects.clear();
      expect(result.toJson()['effects'], hasLength(1));
      expect(
        compileAutomation(
          body: body,
          parameters: {'message': 'unit message\n\n'},
          baselineFingerprints: {'system.motd': 'a' * 64},
          qualifiedRecipes: {},
        ).toJson(),
        result.toJson(),
      );
    },
  );

  test('compilation cannot replace missing baseline or qualification with defaults', () {
    expect(
      () => compileAutomation(
        body: AutomationBody.fromJson(motdBody()),
        parameters: {},
        baselineFingerprints: {},
        qualifiedRecipes: {},
      ),
      safeState('PREFLIGHT_FAILED'),
    );
    final recipe = AutomationBody.fromJson({
      'format': 1,
      'environment': 'ubuntu24.04-amd64-systemd',
      'parameters': <String, Object?>{},
      'steps': [
        {
          'id': 'install',
          'kind': 'install_recipe',
          'recipeDigest': 'b' * 64,
          'version': '1.0',
        },
      ],
    });
    expect(
      () => compileAutomation(
        body: recipe,
        parameters: {},
        baselineFingerprints: {},
        qualifiedRecipes: {},
      ),
      safeState('QUALIFICATION_REQUIRED'),
    );
  });

  test(
    'catalog diff preserves RFC6901 paths, deterministic order and value types',
    () {
      final before = <String, Object?>{
        'z': [1, 2],
        'a/b~': {'v': true},
        'removed': 4,
      };
      final after = <String, Object?>{
        'z': [1, 3, 5],
        'a/b~': {'v': false},
        'added': null,
      };
      final result = profileCatalogDiff(before, after);
      expect(result, {
        'truncated': false,
        'changes': [
          {
            'op': 'replace',
            'path': '/a~1b~0/v',
            'before': true,
            'after': false,
          },
          {'op': 'add', 'path': '/added', 'after': null},
          {'op': 'remove', 'path': '/removed', 'before': 4},
          {'op': 'replace', 'path': '/z/1', 'before': 2, 'after': 3},
          {'op': 'add', 'path': '/z/2', 'after': 5},
        ],
      });
      (before['z'] as List).clear();
      expect((result['changes'] as List)[3], containsPair('before', 2));
    },
  );

  test('catalog diff reports truncation at bounded output and rejects oversized input', () {
    final before = <String, Object?>{for (var i = 0; i < 2100; i++) 'key$i': 0};
    final after = <String, Object?>{for (var i = 0; i < 2100; i++) 'key$i': 1};
    final result = profileCatalogDiff(before, after);
    expect(result['truncated'], isTrue);
    expect(result['changes'], hasLength(2048));
    expect(
      () => profileCatalogDiff({}, {'oversized': 'x' * (128 * 1024)}),
      throwsFormatException,
    );
  });
}
