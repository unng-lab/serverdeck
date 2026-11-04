import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/connections/private_signer.dart';
import 'package:serverdeck/connections/ssh_transport.dart';
import 'package:serverdeck/monitoring/linux_metrics.dart';
import 'package:serverdeck/monitoring/monitoring_models.dart';
import 'package:serverdeck/profiles/credential_parser.dart';
import 'package:serverdeck/runtime/owned_work.dart';

import '../fixtures/ssh_auth_peer.dart';

void main() {
  test(
    'typed transport emits only constant collector and returns parsed values',
    () async {
      final key = parsePrivateKey(
        File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
      );
      final peer = MemoryAuthPeer(hostKey: key.key);
      final verifier = HostSignatureVerifier(), signer = PrivateSigner();
      final parent = WorkCancellation();
      var channelId = -1, executions = 0;
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
          executions++;
          expect(request.requestType, 'exec');
          expect(request.command, linuxMonitoringCommand);
          expect(request.command, isNot(contains('\r')));
          send(SSH_Message_Channel_Success(recipientChannel: channelId));
          send(
            SSH_Message_Channel_Data(
              recipientChannel: channelId,
              data: Uint8List.fromList(
                utf8.encode(
                  'SDM1\nOS\nLinux\nCPU\ncpu 1 2 3 4 5 6 7 8\nMEM\nMemTotal: 1000 kB\nMemAvailable: 250 kB\nDISK\nheader\nroot 1000 400 400 50% /\nEND\n',
                ),
              ),
            ),
          );
          send(
            SSH_Message_Channel_Request.exitStatus(
              recipientChannel: channelId,
              exitStatus: 0,
            ),
          );
          send(SSH_Message_Channel_EOF(recipientChannel: channelId));
          send(SSH_Message_Channel_Close(recipientChannel: channelId));
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
        final sample = await transport.collectMonitoring(WorkCancellation());
        expect(sample.failure, isNull);
        expect(sample.memoryPercent, 75);
        expect(sample.diskPercent, 50);
        expect(sample.cpu!.values, [1, 2, 3, 4, 5, 6, 7, 8]);
        expect(executions, 1);
        final cancelled = WorkCancellation()..cancel();
        expect(
          (await transport.collectMonitoring(cancelled)).failure,
          MonitoringReason.paused,
        );
        expect(executions, 1);
        await transport.ping();
        expect(peer.pings, 1);
      } finally {
        await transport.close();
        await peer.close();
        await verifier.dispose();
        await signer.dispose();
        key.dispose();
      }
      expect(peer.codecFailure, isNull);
    },
  );
}
