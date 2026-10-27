import 'dart:math';

import 'package:serverdeck_locald/api/auth.dart';
import 'package:serverdeck_locald/api/sessions.dart';
import 'package:serverdeck_windows/pipe.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

import 'auth_test.dart' show generation, buildId, token, frame, code;
import '../../serverdeck_windows/test/support/thread_identity_probe.dart';

void main() {
  test('kernel pipe peer/image is verified before hello and grant without identity changes', () async {
    final random = Random.secure();
    final namespace = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final name = '\\\\.\\pipe\\ServerDeckNext.v1.$namespace.0';
    final sid = currentUserSid();
    final server = NativePipe.createServer(name, sid);
    NativePipe? client;
    final sessions = SessionRegistry(generation: generation);
    try {
      final accept = server.accept();
      client = NativePipe.openClient(name, sid);
      await accept;
      final peer = observeThreadIdentity(server.peerIdentity);
      final image = peer.imagePath, hash = fileSha256(peer.imagePath);
      var checks = 0;
      final handshake = ServerHandshake(
        token: token,
        generation: generation,
        buildId: buildId,
        channel: name,
        sessions: sessions,
        verifyPeer: () async {
          observeThreadIdentity(
            () => verifyProcessImage(server.peerIdentity(), sid, image, hash),
          );
          checks++;
        },
      );
      try {
        final hello = await handshake.hello();
        final grant = await handshake.authenticate(
          await frame(hello, ['readiness.read']),
        );
        expect(checks, 2);
        expect(currentUserSid(), sid);
        sessions.begin(name, grant.sessionId, null).complete();
      } finally {
        handshake.close();
      }
      sessions.disconnect(name);
      var originalFailureConfirmed = false;
      final unapproved = ServerHandshake(
        token: token,
        generation: generation,
        buildId: buildId,
        channel: name,
        sessions: sessions,
        verifyPeer: () async {
          try {
            observeThreadIdentity(
              () => verifyProcessImage(
                server.peerIdentity(),
                sid,
                image,
                '0' * 64,
              ),
            );
          } on StateError catch (error) {
            originalFailureConfirmed = error.message == 'IDENTITY_UNAVAILABLE';
            rethrow;
          }
        },
      );
      try {
        await expectLater(unapproved.hello(), code('UNAUTHORIZED'));
        expect(originalFailureConfirmed, true);
        expect(sessions.count, 0);
        expect(currentUserSid(), sid);
      } finally {
        unapproved.close();
      }
    } finally {
      sessions.stop();
      await client?.close();
      await server.close();
    }
  }, testOn: 'windows');
}
