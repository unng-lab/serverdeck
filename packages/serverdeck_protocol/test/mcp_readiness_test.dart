import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-8234-123456789abc';
void main() {
  test(
    'operational identity and partial capability defaults preserve legacy',
    () {
      final view = OperationalReadiness(
        state: ReadinessState.ready,
        generation: generation,
        workspaceId: generation,
      );
      final json = view.toJson();
      expect(json['apiMinor'], 1);
      expect(json['storageSchema'], 2);
      expect(json['reason'], null);
      expect(json['features'], {
        'profiles': false,
        'ssh': false,
        'jobs': false,
        'backend': false,
        'mcp': false,
      });
      expect(OperationalReadiness.decode(view.encode()).toJson(), json);
      (json['features'] as Map)['mcp'] = true;
      expect((view.toJson()['features'] as Map)['mcp'], false);
      final legacy = ReadinessView(
        state: ReadinessState.ready,
        reason: null,
        workspaceId: generation,
        generation: generation,
      ).toJson();
      expect(legacy['apiMinor'], 0);
      expect(legacy['storageSchema'], 1);
      expect((legacy['features'] as Map)['profiles'], true);
    },
  );
  test('closed state reason and capabilities do not manufacture readiness', () {
    for (final state in ReadinessState.values) {
      final view = OperationalReadiness(
        state: state,
        generation: generation,
        workspaceId: state == ReadinessState.ready ? generation : null,
      );
      final source = view.toJson();
      expect(OperationalReadiness.fromJson(source).toJson(), source);
      for (final change in <Map<String, Object?>>[
        {'extra': true},
        {'apiMinor': 0},
        {'apiMinor': 1.0},
        {'storageSchema': 1},
        {'generation': 'bad'},
        {'reason': 'PRIVATE_TEXT'},
        {
          'features': {'mcp': false},
        },
      ]) {
        expect(
          () => OperationalReadiness.fromJson({...source, ...change}),
          throwsFormatException,
        );
      }
      if (state != ReadinessState.ready) {
        expect(
          () => OperationalReadiness(
            state: state,
            generation: generation,
            features: const OperationalFeatures(mcp: true),
          ),
          throwsFormatException,
        );
      }
    }
    expect(
      () => OperationalReadiness(
        state: ReadinessState.ready,
        generation: generation,
      ),
      throwsFormatException,
    );
    final enabled = OperationalReadiness(
      state: ReadinessState.ready,
      generation: generation,
      workspaceId: generation,
      features: const OperationalFeatures(
        profiles: true,
        ssh: true,
        jobs: true,
        backend: true,
        mcp: true,
      ),
    );
    expect(
      OperationalReadiness.decode(enabled.encode()).toJson(),
      enabled.toJson(),
    );
  });
  test('strict bytes reject duplicate fields and oversized readiness', () {
    expect(
      () => OperationalReadiness.decode(
        '{"state":"ready","state":"starting"}'.codeUnits,
      ),
      throwsFormatException,
    );
    expect(
      () => OperationalReadiness.decode(List.filled(8193, 32)),
      throwsFormatException,
    );
  });
}
