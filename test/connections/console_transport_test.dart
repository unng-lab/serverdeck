import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/connections/ssh_transport.dart';
import 'package:serverdeck/console/console_port.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/runtime/owned_work.dart';

import '../fixtures/ssh_auth_peer.dart';

void main() {
  test('lease is rechecked at raw packet admission and denied data does not break cipher', () async {
    final key = parsePrivateKey(
      File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
    );
    final peer = MemoryAuthPeer(hostKey: key.key);
    final verifier = HostSignatureVerifier(), signer = PrivateSigner();
    final parent = WorkCancellation();
    var channelId = -1;
    String? deniedRequest;
    final input = <String>[];
    Completer<void>? hold;
    final entered = Completer<void>();
    void send(SSHMessage message) => peer.sendChannelPacket(message.encode());
    peer.onChannelPacket = (bytes) {
      if (bytes.first == 90) {
        final open = SSH_Message_Channel_Open.decode(bytes);
        channelId = open.senderChannel;
        send(
          SSH_Message_Channel_Confirmation(
            recipientChannel: channelId,
            senderChannel: 7,
            initialWindowSize: 65536,
            maximumPacketSize: 32768,
            data: Uint8List(0),
          ),
        );
      } else if (bytes.first == 98) {
        final request = SSH_Message_Channel_Request.decode(bytes);
        if (request.requestType == deniedRequest) {
          send(SSH_Message_Channel_Failure(recipientChannel: channelId));
        } else {
          send(SSH_Message_Channel_Success(recipientChannel: channelId));
        }
      } else if (bytes.first == 94) {
        input.add(utf8.decode(SSH_Message_Channel_Data.decode(bytes).data));
      } else if (bytes.first == 97) {
        send(SSH_Message_Channel_Close(recipientChannel: channelId));
      }
    };
    final transport = StrictSshTransport(
      socket: peer,
      username: 'unit',
      credential: PasswordCredential(
        Uint8List.fromList(utf8.encode('synthetic-password')),
      ),
      verifier: verifier,
      signer: signer,
      admitWrite: (write) async {
        if (hold != null) {
          if (!entered.isCompleted) entered.complete();
          await hold.future;
        }
        write();
      },
      checkAuthentication: () {},
      verifyHost: (_) async => true,
      changedHost: (_) async {},
      requestPassphrase: () async => null,
      remainingBudget: () => const Duration(seconds: 30),
      cancellation: parent,
    );
    try {
      await transport.authenticated;
      final channel = await transport
          .openConsole(onData: (_) {}, guard: () {})
          .opened;
      var allowed = true;
      final token = WorkCancellation();
      hold = Completer<void>();
      final pending = channel.write(
        Uint8List.fromList(utf8.encode('old\r')),
        guard: () {
          if (!allowed) throw StateError('lease revoked');
        },
        cancellation: token,
      );
      await entered.future;
      allowed = false;
      token.cancel();
      final denied = await pending;
      expect(denied.acceptedBytes, 0);
      expect(denied.status, 'cancelledBeforeSend');
      expect(input, isEmpty);
      expect(transport.isClosed, isFalse);
      expect(transport.consolePacketWaiterCount, 0);
      for (var i = 0; i < 65; i++) {
        final cancelled = WorkCancellation();
        final waiting = channel.write(
          Uint8List.fromList([65]),
          guard: () {},
          cancellation: cancelled,
        );
        await Future<void>.delayed(Duration.zero);
        cancelled.cancel();
        expect((await waiting).acceptedBytes, 0);
        expect(transport.consoleAdmissionCount, lessThanOrEqualTo(64));
      }
      hold.complete();
      await Future<void>.delayed(Duration.zero);
      hold = null;
      final next = await channel.write(
        Uint8List.fromList(utf8.encode('new\r')),
        guard: () {},
        cancellation: WorkCancellation(),
      );
      expect(next.status, 'complete');
      await Future<void>.delayed(Duration.zero);
      expect(input, ['new\r']);
      expect(transport.isClosed, isFalse);
      // A committed fragment remains encrypted/in FIFO while cancellation ends
      // the action promptly and removes all drain/rekey wait subscriptions.
      peer.holdFlush = Completer<void>();
      peer.flushEntered = Completer<void>();
      final partialToken = WorkCancellation();
      final partial = channel.write(
        Uint8List(65536),
        guard: () {},
        cancellation: partialToken,
      );
      await peer.flushEntered!.future;
      partialToken.cancel();
      final unknown = await partial;
      expect(unknown.status, 'outcomeUnknown');
      expect(unknown.acceptedBytes, 32768);
      expect(transport.consolePacketWaiterCount, 0);
      for (var i = 0; i < 4; i++) {
        final waitingToken = WorkCancellation();
        final waiting = channel.write(
          Uint8List.fromList([65]),
          guard: () {},
          cancellation: waitingToken,
        );
        await Future<void>.delayed(Duration.zero);
        waitingToken.cancel();
        expect((await waiting).acceptedBytes, 0);
        expect(transport.consolePacketWaiterCount, 0);
      }
      peer.holdFlush!.complete();
      peer.holdFlush = null;
      await Future<void>.delayed(Duration.zero);
      input.clear();
      peer.holdRekeyReply = true;
      peer.rekeyHeld = Completer<void>();
      peer.beginRekey(key.key);
      await peer.rekeyHeld!.future;
      final rekeyToken = WorkCancellation();
      final duringRekey = channel.write(
        Uint8List.fromList([65]),
        guard: () {},
        cancellation: rekeyToken,
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.consolePacketWaiterCount, greaterThan(0));
      rekeyToken.cancel();
      expect((await duringRekey).acceptedBytes, 0);
      expect(transport.consolePacketWaiterCount, 0);
      peer.releaseRekey();
      final afterRekey = await channel.write(
        Uint8List.fromList([66]),
        guard: () {},
        cancellation: WorkCancellation(),
      );
      expect(afterRekey.status, 'complete');
      expect(transport.consolePacketWaiterCount, 0);
      channel.abort();
      for (final refusal in [
        ('pty-req', ConsoleOpenFailureCode.ptyDenied),
        ('shell', ConsoleOpenFailureCode.shellDenied),
      ]) {
        deniedRequest = refusal.$1;
        await expectLater(
          transport.openConsole(onData: (_) {}, guard: () {}).opened,
          throwsA(
            isA<ConsoleOpenFailure>().having((e) => e.code, 'code', refusal.$2),
          ),
        );
        expect(transport.isClosed, false);
      }
    } finally {
      if (hold != null && !hold.isCompleted) hold.complete();
      await transport.close();
      await peer.close();
      await verifier.dispose();
      await signer.dispose();
    }
  });
}
