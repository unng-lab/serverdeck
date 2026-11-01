import 'dart:async';

import 'package:serverdeck_engine/api/owner_api.dart';
import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:test/test.dart';

import 'sessions_test.dart' as sessionFixture;

const id = '12345678-1234-4234-9234-123456789abe';
const workspace = '12345678-1234-4234-9234-123456789abf';
Matcher failure(String code) =>
    throwsA(isA<EngineCallFailure>().having((e) => e.code, 'safe code', code));
Map<String, Object?> settings() => {
  'storeRevision': '1',
  'settings': {
    'revision': '1',
    'theme': 'system',
    'reduceMotion': false,
    'selectedProfileId': null,
  },
};

// Dispatcher fake owns no storage or transport. Domain DTO/CAS tests remain in
// their own suites; these tests exercise owner admission and boundary lifetime.
final class Services implements TrustedOwnerApi {
  int prepared = 0, effects = 0, closed = 0;
  bool failClose = false;
  void Function(SessionRequest, Map<String, Object?>)? onPrepare;
  Future<Map<String, Object?>> Function(SessionRequest, Map<String, Object?>)?
  effect;
  @override
  bool supports(String method) => const {
    'settings.get',
    'settings.update',
    'profiles.update',
    'automation.profiles.list',
  }.contains(method);
  @override
  TrustedOwnerInvocation prepare(
    SessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    prepared++;
    onPrepare?.call(request, params);
    return TrustedOwnerInvocation(
      request,
      () {
        expect(request.initialAdmissionProved, isTrue);
        effects++;
        return effect?.call(request, params) ?? Future.value(settings());
      },
      onClose: () {
        closed++;
        if (failClose) throw StateError('private cleanup details');
      },
    );
  }
}

final class Setup {
  Setup(this.auth, this.owner);
  final sessionFixture.Setup auth;
  final OwnerSession owner;
  final services = Services();
  ReadinessState state = ReadinessState.ready;
  String? alternateGeneration;
  TrustedReadiness get readiness => TrustedReadiness(
    state: state,
    generation: alternateGeneration ?? owner.generation,
    workspaceId: state == ReadinessState.ready ? workspace : null,
    features: state == ReadinessState.ready
        ? const OperationalFeatures(profiles: true)
        : const OperationalFeatures(),
  );
  late final gateway = InProcessGateway(
    owner: owner,
    services: services,
    readiness: () => readiness,
  );
  static Future<Setup> create() async {
    final a = await sessionFixture.Setup.create();
    return Setup(a, await a.owner());
  }

  Future<void> close() async {
    await gateway.close();
    await auth.close();
  }
}

void main() {
  test(
    'JSON boundary preserves Unicode text/keys and finite metric numbers',
    () async {
      final s = await Setup.create();
      final value = <String, Object?>{
        'text': 'e\u0301',
        'ratio': 1.25,
        'e\u0301': 'decomposed',
        '\u00e9': 'composed',
      };
      s.services.effect = (_, params) async => params;
      final result = await s.gateway.call(
        'profiles.update',
        value,
        requestId: id,
      );
      expect(result, value);
      expect(
        result.keys.where((key) => key != 'text' && key != 'ratio').length,
        2,
      );
      await expectLater(
        s.gateway.call('profiles.update', {'ratio': double.nan}, requestId: id),
        failure('VALIDATION'),
      );
      await s.close();
    },
  );

  test('whole-message byte budgets include metadata rather than expanding payload limits', () async {
    final s = await Setup.create();
    await expectLater(
      s.gateway.call('profiles.update', {
        'value': 'x' * (maxRequestBytes - 100),
      }, requestId: id),
      failure('VALIDATION'),
    );
    expect(s.services.prepared, 0);
    s.services.effect = (_, _) async => {
      'value': 'x' * (maxResponseBytes - 100),
    };
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: id),
      failure('INTERNAL'),
    );
    await s.close();
  });

  test(
    'typed owner invocation has fresh admission and immutable detached result',
    () async {
      final s = await Setup.create();
      final source = settings();
      s.services.effect = (_, _) async => source;
      final result = await s.gateway.call('settings.get', {}, requestId: id);
      (source['settings'] as Map)['theme'] = 'dark';
      expect((result['settings'] as Map)['theme'], 'system');
      expect(
        () => (result['settings'] as Map)['theme'] = 'dark',
        throwsUnsupportedError,
      );
      expect(s.services.effects, 1);
      expect(s.services.closed, 1);
      expect(s.gateway.generation, s.owner.generation);
      await s.close();
    },
  );

  test('params are captured before awaited proof and source mutation cannot change intent', () async {
    final s = await Setup.create();
    final input = <String, Object?>{
      'patch': <String, Object?>{'label': 'before'},
    };
    final pause = s.auth.runtime.paused = Completer<void>();
    String? captured;
    s.services.effect = (_, params) async {
      captured = (params['patch'] as Map)['label'] as String;
      return settings();
    };
    final work = s.gateway.call('profiles.update', input, requestId: id);
    (input['patch'] as Map)['label'] = 'after';
    pause.complete();
    await work;
    expect(captured, 'before');
    await s.close();
  });

  test('readiness and builtins keep their DTO while domain routes stay closed before Ready', () async {
    final s = await Setup.create()
      ..state = ReadinessState.starting;
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: id),
      failure('NOT_READY'),
    );
    final view = await s.gateway.call('readiness.get', {}, requestId: id);
    expect(view, s.readiness.toJson());
    expect(view['storageSchema'], 3);
    expect(await s.gateway.call('session.ping', {}, requestId: id), {
      'leaseSeconds': 60,
    });
    expect(s.services.prepared, 0);
    s.state = ReadinessState.storageBlocked;
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: id),
      failure('STORAGE_BLOCKED'),
    );
    await s.close();
  });

  test('MCP method gate precedes invalid payload and unknown owner methods do not run services', () async {
    final s = await Setup.create();
    await expectLater(
      s.gateway.call('mcp.invoke', {'invalid': Object()}, requestId: id),
      failure('FORBIDDEN'),
    );
    await expectLater(
      s.gateway.call('unknown.action', {}, requestId: id),
      failure('UNSUPPORTED'),
    );
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: 'bad'),
      failure('VALIDATION'),
    );
    expect(s.services.prepared, 0);
    expect(s.services.effects, 0);
    await s.close();
  });

  test('catalog projection is bounded and frozen without inventing another response schema', () async {
    final s = await Setup.create();
    s.services.effect = (_, _) async => {
      'items': [
        <String, Object?>{'id': workspace},
      ],
      'nextOffset': null,
    };
    final result = await s.gateway.call(
      'automation.profiles.list',
      {},
      requestId: id,
    );
    expect(() => (result['items'] as List).clear(), throwsUnsupportedError);
    expect(
      () => ((result['items'] as List).single as Map).clear(),
      throwsUnsupportedError,
    );
    await s.close();
  });

  test(
    'provider errors and invalid output expose only fixed public categories',
    () async {
      final s = await Setup.create();
      s.services.effect = (_, _) async =>
          throw StateError('private-provider-secret');
      await expectLater(
        s.gateway.call('settings.get', {}, requestId: id),
        failure('INTERNAL'),
      );
      s.services.effect = (_, _) async => throw StateError('REVISION_CONFLICT');
      await expectLater(
        s.gateway.call('settings.get', {}, requestId: id),
        failure('REVISION_CONFLICT'),
      );
      s.services.effect = (_, _) async => {'bad': Object()};
      await expectLater(
        s.gateway.call('settings.get', {}, requestId: id),
        failure('INTERNAL'),
      );
      expect(
        EngineCallFailure('CONNECTION_FAILED').toJson()['retry'],
        'reconnect',
      );
      await s.close();
    },
  );

  test(
    'caller timeout does not release physical proof or make close finish early',
    () async {
      final s = await Setup.create();
      final pause = Completer<void>();
      s.services.onPrepare = (_, _) {
        s.auth.elapsed =
            const Duration(seconds: 5) - const Duration(microseconds: 1);
        s.auth.runtime.paused = pause;
      };
      final reply = s.gateway.call('settings.get', {}, requestId: id);
      await expectLater(
        reply.timeout(const Duration(milliseconds: 200)),
        failure('TIMEOUT'),
      );
      var closed = false;
      final closing = s.gateway.close().then((_) => closed = true);
      await sessionFixture.settle();
      expect(closed, isFalse);
      expect(s.services.effects, 0);
      pause.complete();
      await closing;
      expect(s.services.closed, 1);
      await s.auth.close();
    },
  );

  test('16 pending owner calls remain bounded and close discards their late results', () async {
    final s = await Setup.create();
    final effect = Completer<Map<String, Object?>>();
    s.services.effect = (_, _) => effect.future;
    final calls = [
      for (var i = 0; i < 16; i++)
        s.gateway.call('settings.get', {}, requestId: id),
    ];
    final denied = [
      for (final call in calls)
        expectLater(call, failure('SERVICE_UNAVAILABLE')),
    ];
    await sessionFixture.settle();
    expect(s.services.effects, 16);
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: id),
      failure('RESOURCE_LIMIT'),
    );
    var closed = false;
    final closing = s.gateway.close().then((_) => closed = true);
    await sessionFixture.settle();
    expect(closed, isFalse);
    effect.complete(settings());
    await Future.wait(denied);
    await closing;
    expect(s.services.closed, 16);
    await s.auth.close();
  });

  test('owner revocation, readiness change and generation mismatch cannot publish stale output', () async {
    final s = await Setup.create();
    final effect = Completer<Map<String, Object?>>();
    s.services.effect = (_, _) => effect.future;
    final reply = s.gateway.call('settings.get', {}, requestId: id);
    final denied = expectLater(reply, failure('SERVICE_UNAVAILABLE'));
    await sessionFixture.settle();
    s.state = ReadinessState.stopping;
    effect.complete(settings());
    await denied;
    s.state = ReadinessState.ready;
    s.alternateGeneration = workspace;
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: id),
      failure('INTERNAL'),
    );
    s.alternateGeneration = null;
    s.owner.close();
    await expectLater(
      s.gateway.call('settings.get', {}, requestId: id),
      failure('UNAUTHORIZED'),
    );
    await s.close();
  });

  test('session.close is logical retirement and failed invocation cleanup cannot become a clean close', () async {
    final s = await Setup.create();
    expect(await s.gateway.call('session.close', {}, requestId: id), {
      'closed': true,
    });
    expect(s.gateway.isClosed, isTrue);
    await expectLater(
      s.gateway.call('session.ping', {}, requestId: id),
      failure('SERVICE_UNAVAILABLE'),
    );
    await s.close();
    final failing = await Setup.create()
      ..services.failClose = true;
    await expectLater(
      failing.gateway.call('settings.get', {}, requestId: id),
      failure('SERVICE_UNAVAILABLE'),
    );
    expect(failing.gateway.isClosed, isTrue);
    await expectLater(failing.gateway.close(), failure('SERVICE_UNAVAILABLE'));
    await failing.auth.close();
  });
}
