import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_locald/api/auth.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-8234-123456789abc';
final buildId = '${'a' * 40}+Debug+${'b' * 64}';
final token = List.generate(32, (i) => i);
final clientNonce = base64Url.encode(List.filled(32, 9)).replaceAll('=', '');
Matcher code(String value) =>
    throwsA(isA<StateError>().having((e) => e.message, 'safe code', value));

Future<String> proof(String transcript, [List<int>? key]) async => base64Url
    .encode(
      (await Hmac.sha256().calculateMac(
        utf8.encode(transcript),
        secretKey: SecretKey(key ?? token),
      )).bytes,
    )
    .replaceAll('=', '');
String transcript(
  ServerHello hello,
  List<String> caps, {
  String role = 'client',
  String? sessionId,
}) =>
    '$role\n1\ndefault\n$generation\n${hello.serverNonce}\n$clientNonce\n$buildId\n${caps.join(',')}${sessionId == null ? '' : '\n$sessionId\n${caps.join(',')}'}';
Future<List<int>> frame(
  ServerHello hello,
  List<String> caps, {
  String? digest,
  String? clientBuild,
}) async => StrictCodec().encode(
  Authenticate(
    clientNonce: clientNonce,
    clientBuildId: clientBuild ?? buildId,
    requestedCapabilities: caps,
    proof: digest ?? await proof(transcript(hello, caps)),
  ).toJson(),
);

void main() {
  test('peer checks precede hello and grant, transcript and read-only grants are exact', () async {
    final events = <String>[];
    final sessions = SessionRegistry(generation: generation);
    final ownedToken = List<int>.of(token);
    final handshake = ServerHandshake(
      token: ownedToken,
      generation: generation,
      buildId: buildId,
      channel: 'pipe-a',
      sessions: sessions,
      verifyPeer: () async {
        events.add('peer');
      },
    );
    ownedToken.fillRange(0, 32, 0);
    final hello = await handshake.hello();
    validateHello(hello.toJson());
    expect(events, ['peer']);
    expect(sessions.count, 0);
    final caps = ['profiles.read', 'readiness.read'];
    final grant = await handshake.authenticate(await frame(hello, caps));
    validateAuthenticated(grant.toJson());
    expect(events, ['peer', 'peer']);
    expect(grant.capabilities, caps);
    expect(
      grant.proof,
      await proof(
        transcript(hello, caps, role: 'server', sessionId: grant.sessionId),
      ),
    );
    expect(sessions.count, 1);
    final read = sessions.begin(
      'pipe-a',
      grant.sessionId,
      Capability.profilesRead,
    );
    read.complete();
    read.complete();
    expect(
      () => sessions.begin('pipe-a', grant.sessionId, Capability.profilesWrite),
      code('FORBIDDEN'),
    );
    await expectLater(
      handshake.authenticate(await frame(hello, caps)),
      code('UNAUTHORIZED'),
    );
    handshake.close();
    sessions.stop();
  });

  test('failed initial/repeated peer check, proof, capability or build creates no session', () async {
    for (final mode in [
      'initial',
      'repeated',
      'proof',
      'capability',
      'build',
      'extra',
    ]) {
      final sessions = SessionRegistry(generation: generation);
      var checks = 0;
      final handshake = ServerHandshake(
        token: token,
        generation: generation,
        buildId: buildId,
        channel: mode,
        sessions: sessions,
        verifyPeer: () async {
          checks++;
          if ((mode == 'initial' && checks == 1) ||
              (mode == 'repeated' && checks == 2))
            throw StateError('IDENTITY_UNAVAILABLE');
        },
      );
      if (mode == 'initial') {
        await expectLater(handshake.hello(), code('UNAUTHORIZED'));
      } else {
        final hello = await handshake.hello();
        final caps = mode == 'capability'
            ? ['executor.run']
            : ['readiness.read'];
        var input = await frame(
          hello,
          caps,
          digest: mode == 'proof' ? clientNonce : null,
          clientBuild: mode == 'build' ? 'wrong' : null,
        );
        if (mode == 'extra')
          input = StrictCodec().encode({
            'authenticate': {
              ...(StrictCodec().decode(input)['authenticate']
                  as Map<String, Object?>),
              'pid': 123,
            },
          });
        await expectLater(
          handshake.authenticate(input),
          code(mode == 'build' ? 'INCOMPATIBLE' : 'UNAUTHORIZED'),
        );
        await expectLater(handshake.authenticate(input), code('UNAUTHORIZED'));
      }
      expect(sessions.count, 0);
      handshake.close();
      sessions.stop();
    }
  });

  test(
    'handshake expiration or close during peer query cannot grant later',
    () async {
      var time = Duration.zero;
      final sessions = SessionRegistry(generation: generation);
      final handshake = ServerHandshake(
        token: token,
        generation: generation,
        buildId: buildId,
        channel: 'expired',
        sessions: sessions,
        elapsed: () => time,
        verifyPeer: () async {},
      );
      final hello = await handshake.hello();
      time = const Duration(seconds: 5);
      await expectLater(
        handshake.authenticate(await frame(hello, ['readiness.read'])),
        code('TIMEOUT'),
      );
      expect(sessions.count, 0);
      sessions.stop();
      final pendingPeer = Completer<void>();
      final stoppedSessions = SessionRegistry(generation: generation);
      var queries = 0;
      final stopped = ServerHandshake(
        token: token,
        generation: generation,
        buildId: buildId,
        channel: 'closed',
        sessions: stoppedSessions,
        verifyPeer: () async {
          queries++;
          if (queries == 2) await pendingPeer.future;
        },
      );
      final challenge = await stopped.hello();
      final response = stopped.authenticate(
        await frame(challenge, ['readiness.read']),
      );
      final rejected = expectLater(response, code('UNAUTHORIZED'));
      stopped.close();
      pendingPeer.complete();
      await rejected;
      expect(stoppedSessions.count, 0);
      stoppedSessions.stop();
    },
  );
}
