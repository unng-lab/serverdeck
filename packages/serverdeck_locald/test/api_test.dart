import 'dart:convert';

import 'package:serverdeck_locald/api/server.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-9234-123456789abc';
final session = base64Url.encode(List.filled(32, 7)).replaceAll('=', '');
List<int> request(
  String method, {
  Map<String, Object?> params = const {},
  String? sessionId,
}) => StrictCodec().encode(
  ApiRequest(
    id: generation,
    sessionId: sessionId ?? session,
    method: method,
    params: params,
  ).toJson(),
);
void main() {
  test('safe readiness errors do not expose backend exceptions or admit ordinary requests', () async {
    final sessions = SessionRegistry(generation: generation)
      ..register('channel', session, Capability.values.toSet());
    var state = ReadinessState.starting;
    final server = ApiServer(
      sessions: sessions,
      readiness: () => ReadinessView(
        state: state,
        reason: null,
        workspaceId: state == ReadinessState.ready ? generation : null,
        generation: generation,
      ),
      coordinator: () => throw StateError('PRIVATE_BACKEND_SECRET'),
    );
    try {
      for (final candidate in ReadinessState.values) {
        state = candidate;
        final response = await server.handle(
          'channel',
          request('profiles.list'),
        );
        final value = StrictCodec().decode(response.bytes);
        expect((value['error'] as Map)['code'], switch (candidate) {
          ReadinessState.storageBlocked => 'STORAGE_BLOCKED',
          ReadinessState.incompatible => 'INCOMPATIBLE',
          ReadinessState.ready => 'INTERNAL',
          _ => 'NOT_READY',
        });
        expect(
          utf8.decode(response.bytes),
          isNot(contains('PRIVATE_BACKEND_SECRET')),
        );
      }
    } finally {
      sessions.stop();
    }
  });
  test(
    'all ordinary methods gate before business validation and backend lookup',
    () async {
      final sessions = SessionRegistry(generation: generation)
        ..register('channel', session, Capability.values.toSet());
      var backendLookups = 0;
      final server = ApiServer(
        sessions: sessions,
        readiness: () => const ReadinessView(
          state: ReadinessState.starting,
          reason: null,
          workspaceId: null,
          generation: generation,
        ),
        coordinator: () {
          backendLookups++;
          return null;
        },
      );
      try {
        for (final method in ApiMethod.values.where((m) => m.requiresReady)) {
          final response = StrictCodec().decode(
            (await server.handle(
              'channel',
              request(
                method.wireName,
                params: {'privateKey': 'synthetic-secret', 'unknown': 'bad'},
              ),
            )).bytes,
          );
          expect((response['error'] as Map)['code'], 'NOT_READY');
          expect(
            utf8.decode(StrictCodec().encode(response)),
            isNot(contains('synthetic-secret')),
          );
        }
        expect(backendLookups, 0);
        expect(
          StrictCodec().decode(
            (await server.handle('channel', request('readiness.get'))).bytes,
          )['result'],
          isA<Map>(),
        );
        expect(
          StrictCodec().decode(
            (await server.handle('channel', request('session.ping'))).bytes,
          )['result'],
          {'leaseSeconds': 60},
        );
        final closed = await server.handle('channel', request('session.close'));
        expect(closed.closeChannel, true);
        expect(sessions.count, 0);
      } finally {
        sessions.stop();
      }
    },
  );
  test('cap checks precede params validation, unknown methods authenticate, invalid envelope closes', () async {
    final sessions = SessionRegistry(generation: generation)
      ..register('channel', session, {Capability.readinessRead});
    final server = ApiServer(
      sessions: sessions,
      readiness: () => const ReadinessView(
        state: ReadinessState.starting,
        reason: null,
        workspaceId: null,
        generation: generation,
      ),
      coordinator: () => throw StateError('PRIVATE_UNSAFE_BACKEND_TEXT'),
    );
    try {
      for (final method in ApiMethod.values.where(
        (m) => m.capability != null && m.capability != Capability.readinessRead,
      )) {
        final decoded = StrictCodec().decode(
          (await server.handle(
            'channel',
            request(method.wireName, params: {'bad': 'private input'}),
          )).bytes,
        );
        expect((decoded['error'] as Map)['code'], 'FORBIDDEN');
      }
      expect(
        (StrictCodec().decode(
              (await server.handle(
                'channel',
                request('ssh.execute', params: {'password': 'secret'}),
              )).bytes,
            )['error']
            as Map)['code'],
        'UNSUPPORTED',
      );
      await expectLater(
        server.handle('foreign', request('ssh.execute')),
        throwsStateError,
      );
      await expectLater(server.handle('channel', [0xff]), throwsStateError);
      final pending = List.generate(
        16,
        (_) => sessions.begin('channel', session, null),
      );
      expect(
        (StrictCodec().decode(
              (await server.handle('channel', request('session.ping'))).bytes,
            )['error']
            as Map)['code'],
        'RESOURCE_LIMIT',
      );
      for (final p in pending) {
        p.complete();
      }
      expect(
        (StrictCodec().decode(
              (await server.handle(
                'channel',
                request('session.ping', params: {'extra': true}),
              )).bytes,
            )['error']
            as Map)['code'],
        'VALIDATION',
      );
    } finally {
      sessions.stop();
    }
  });
}
