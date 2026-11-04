import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:dartssh2/src/ssh_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/connections/host_signature.dart';
import 'package:serverdeck/profiles/credential_parser.dart';

import '../fixtures/ssh_auth_peer.dart';

Future<void> turns() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class ChannelHarness {
  ChannelHarness() {
    peer = MemoryAuthPeer(hostKey: host.key);
    peer.onChannelPacket = (bytes) {
      packets.add(bytes.first);
      switch (bytes.first) {
        case 90:
          final open = SSH_Message_Channel_Open.decode(bytes);
          opens.add(open);
          onOpen?.call(open);
        case 98:
          final request = SSH_Message_Channel_Request.decode(bytes);
          requests.add(request);
          onRequest?.call(request);
        case 97:
          closes++;
          if (replyClose)
            send(
              SSH_Message_Channel_Close(
                recipientChannel: opens.last.senderChannel,
              ),
            );
        default:
          break;
      }
    };
    client = SSHClient(
      peer,
      username: 'unit',
      onPasswordRequest: () => 'synthetic-password',
      onVerifyHostSignature: verifier.verify,
      onVerifyHostKey: (_, _, _) => true,
      onHostKeyChanged: (_, _, _) {},
      keepAliveInterval: null,
      handshakeTimeout: null,
      authTimeout: null,
    );
    client.done.ignore();
  }
  final host = parseOpenSshKey(
    File('test/fixtures/ssh/ed25519.txt').readAsBytesSync(),
  );
  final verifier = HostSignatureVerifier();
  late final MemoryAuthPeer peer;
  late final SSHClient client;
  final opens = <SSH_Message_Channel_Open>[];
  final requests = <SSH_Message_Channel_Request>[];
  final packets = <int>[];
  int closes = 0;
  bool replyClose = true;
  void Function(SSH_Message_Channel_Open)? onOpen;
  void Function(SSH_Message_Channel_Request)? onRequest;
  void send(SSHMessage message) => peer.sendChannelPacket(message.encode());
  void accept() => send(
    SSH_Message_Channel_Confirmation(
      recipientChannel: opens.last.senderChannel,
      senderChannel: 71,
      initialWindowSize: 65536,
      maximumPacketSize: 32768,
      data: Uint8List(0),
    ),
  );
  void data(int length, {int? type}) {
    final id = opens.last.senderChannel;
    send(
      type == null
          ? SSH_Message_Channel_Data(
              recipientChannel: id,
              data: Uint8List(length),
            )
          : SSH_Message_Channel_Extended_Data(
              recipientChannel: id,
              dataTypeCode: type,
              data: Uint8List(length),
            ),
    );
  }

  void finish({int? status = 0}) {
    final id = opens.last.senderChannel;
    if (status != null)
      send(
        SSH_Message_Channel_Request.exitStatus(
          recipientChannel: id,
          exitStatus: status,
        ),
      );
    send(SSH_Message_Channel_EOF(recipientChannel: id));
    send(SSH_Message_Channel_Close(recipientChannel: id));
  }

  Future<void> dispose() async {
    await client.close();
    await peer.close();
    await verifier.dispose();
    host.dispose();
    expect(peer.codecFailure, isNull);
  }
}

void main() {
  test(
    'bounded exec reads early output with no PTY/environment/stdin requests',
    () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      h.onOpen = (_) {
        h.accept();
        h.data(7);
      };
      h.onRequest = (_) {
        h.send(
          SSH_Message_Channel_Success(
            recipientChannel: h.opens.last.senderChannel,
          ),
        );
        h.data(9, type: 1);
        h.finish();
      };
      final result = await h.client
          .startBoundedExec('synthetic constant')
          .result;
      expect(result.failure, isNull);
      expect(result.stdout, hasLength(7));
      expect(result.exitCode, 0);
      expect(h.opens.single.initialWindowSize, 65536);
      expect(h.opens.single.maximumPacketSize, lessThanOrEqualTo(32768));
      expect(h.requests.map((r) => r.requestType), ['exec']);
      expect(h.requests.single.command, 'synthetic constant');
    },
  );

  test(
    'cancel pending open retains one slot and late success never executes',
    () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      h.replyClose = false;
      final op = h.client.startBoundedExec('synthetic');
      await turns();
      op.cancel();
      op.cancel();
      expect((await op.result).failure, SSHBoundedExecFailure.cancelled);
      expect(
        (await h.client.startBoundedExec('another').result).failure,
        SSHBoundedExecFailure.cleanupPending,
      );
      expect(h.opens, hasLength(1));
      h.accept();
      await turns();
      expect(h.requests, isEmpty);
      expect(h.closes, 1);
      h.data(12);
      await turns();
      expect(h.packets.where((p) => p == 93), isEmpty);
      h.send(
        SSH_Message_Channel_Close(recipientChannel: h.opens.last.senderChannel),
      );
      await turns();
      h.onOpen = (_) => h.accept();
      h.onRequest = (_) {
        h.send(
          SSH_Message_Channel_Success(
            recipientChannel: h.opens.last.senderChannel,
          ),
        );
        h.finish();
      };
      expect((await h.client.startBoundedExec('next').result).failure, isNull);
    },
  );

  test(
    'late open failure releases cancelled tombstone without closing SSH',
    () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      final op = h.client.startBoundedExec('synthetic');
      await turns();
      op.cancel();
      await op.result;
      h.send(
        SSH_Message_Channel_Open_Failure(
          recipientChannel: h.opens.last.senderChannel,
          reasonCode: 1,
          description: 'untrusted reason',
          languageTag: '',
        ),
      );
      await turns();
      h.onOpen = (_) => h.accept();
      h.onRequest = (_) {
        h.send(
          SSH_Message_Channel_Success(
            recipientChannel: h.opens.last.senderChannel,
          ),
        );
        h.finish();
      };
      expect((await h.client.startBoundedExec('next').result).failure, isNull);
      expect(h.client.isClosed, isFalse);
    },
  );

  for (final extra in [false, true]) {
    test(
      'counts every extended-data kind and rejects crossing packet extra=$extra',
      () async {
        final h = ChannelHarness();
        addTearDown(h.dispose);
        await h.client.authenticated;
        h.onOpen = (_) => h.accept();
        h.onRequest = (_) {
          h.send(
            SSH_Message_Channel_Success(
              recipientChannel: h.opens.last.senderChannel,
            ),
          );
          h.data(32768);
          h.data(32768, type: 99);
          if (extra) {
            h.data(1);
          } else {
            h.finish();
          }
        };
        final result = await h.client.startBoundedExec('synthetic').result;
        expect(
          result.failure,
          extra ? SSHBoundedExecFailure.outputLimit : isNull,
        );
        expect(result.stdout.length, lessThanOrEqualTo(65536));
        expect(h.client.isClosed, isFalse);
      },
    );
  }

  test(
    'timeout before exec ACK retires channel and suppresses future allocations',
    () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      h.replyClose = false;
      h.onOpen = (_) => h.accept();
      final op = h.client.startBoundedExec(
        'synthetic',
        timeout: const Duration(milliseconds: 100),
      );
      expect((await op.result).failure, SSHBoundedExecFailure.timeout);
      expect(h.requests, hasLength(1));
      final grants = h.packets.where((p) => p == 93).length;
      h.data(100);
      h.send(
        SSH_Message_Channel_Success(
          recipientChannel: h.opens.last.senderChannel,
        ),
      );
      await turns();
      expect(h.packets.where((p) => p == 93).length, grants);
      expect(
        (await h.client.startBoundedExec('another').result).failure,
        SSHBoundedExecFailure.cleanupPending,
      );
      expect(h.opens, hasLength(1));
    },
  );

  test('duplicate ACK cannot be queued as a future request reply', () async {
    final h = ChannelHarness();
    addTearDown(h.dispose);
    await h.client.authenticated;
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) {
      h.send(
        SSH_Message_Channel_Success(
          recipientChannel: h.opens.last.senderChannel,
        ),
      );
      h.send(
        SSH_Message_Channel_Success(
          recipientChannel: h.opens.last.senderChannel,
        ),
      );
    };
    final result = await h.client.startBoundedExec('synthetic').result;
    expect(result.failure, SSHBoundedExecFailure.invalidResponse);
    expect(h.requests, hasLength(1));
  });

  test('timeout while open is unanswered keeps a single tombstone', () async {
    final h = ChannelHarness();
    addTearDown(h.dispose);
    await h.client.authenticated;
    final result = await h.client
        .startBoundedExec(
          'synthetic',
          timeout: const Duration(milliseconds: 100),
        )
        .result;
    expect(result.failure, SSHBoundedExecFailure.timeout);
    expect(
      (await h.client.startBoundedExec('blocked').result).failure,
      SSHBoundedExecFailure.cleanupPending,
    );
    expect(h.opens, hasLength(1));
    expect(h.requests, isEmpty);
  });

  test(
    'transport close releases local pending work without waiting for timeout',
    () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      final op = h.client.startBoundedExec('synthetic');
      await turns();
      await h.client.close();
      expect((await op.result).failure, isNotNull);
      expect(h.requests, isEmpty);
    },
  );

  test('immediate cancellation prevents allocation before authenticated await resumes', () async {
    final h = ChannelHarness();
    addTearDown(h.dispose);
    await h.client.authenticated;
    final op = h.client.startBoundedExec('synthetic');
    op.cancel();
    expect((await op.result).failure, SSHBoundedExecFailure.cancelled);
    await turns();
    expect(h.opens, isEmpty);
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) {
      h.send(
        SSH_Message_Channel_Success(
          recipientChannel: h.opens.last.senderChannel,
        ),
      );
      h.finish();
    };
    expect((await h.client.startBoundedExec('next').result).failure, isNull);
  });

  test('output limit applies before exec ACK', () async {
    final h = ChannelHarness();
    addTearDown(h.dispose);
    await h.client.authenticated;
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) {
      h.data(32768);
      h.data(32768, type: 7);
      h.data(1);
    };
    expect(
      (await h.client.startBoundedExec('synthetic').result).failure,
      SSHBoundedExecFailure.outputLimit,
    );
  });

  test(
    'ordinary execute keeps the original window and buffered stream behavior',
    () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      h.onOpen = (_) => h.accept();
      h.onRequest = (_) {
        h.send(
          SSH_Message_Channel_Success(
            recipientChannel: h.opens.last.senderChannel,
          ),
        );
        h.data(3);
        h.finish();
      };
      final session = await h.client.execute('ordinary synthetic');
      expect(
        await session.stdout.fold<int>(
          0,
          (count, bytes) => count + bytes.length,
        ),
        3,
      );
      expect(h.opens.single.initialWindowSize, 2 * 1024 * 1024);
    },
  );

  for (final violation in ['duplicateAck', 'oversizedPacket']) {
    test(
      'local abort after status zero is never successful: $violation',
      () async {
        final h = ChannelHarness();
        addTearDown(h.dispose);
        await h.client.authenticated;
        h.replyClose = false;
        h.onOpen = (_) => h.accept();
        h.onRequest = (_) {
          final id = h.opens.last.senderChannel;
          h.send(SSH_Message_Channel_Success(recipientChannel: id));
          h.data(5);
          h.send(
            SSH_Message_Channel_Request.exitStatus(
              recipientChannel: id,
              exitStatus: 0,
            ),
          );
          if (violation == 'duplicateAck') {
            h.send(SSH_Message_Channel_Success(recipientChannel: id));
          } else {
            h.data(32769);
          }
        };
        final result = await h.client.startBoundedExec('synthetic').result;
        expect(result.failure, SSHBoundedExecFailure.invalidResponse);
        expect(result.stdout, isEmpty);
        expect(
          (await h.client.startBoundedExec('blocked').result).failure,
          SSHBoundedExecFailure.cleanupPending,
        );
        final grants = h.packets.where((p) => p == 93).length;
        h.data(200);
        await turns();
        expect(h.packets.where((p) => p == 93).length, grants);
        h.send(
          SSH_Message_Channel_Close(
            recipientChannel: h.opens.last.senderChannel,
          ),
        );
        await turns();
        h.onRequest = (_) {
          h.send(
            SSH_Message_Channel_Success(
              recipientChannel: h.opens.last.senderChannel,
            ),
          );
          h.finish();
        };
        expect(
          (await h.client.startBoundedExec('recovered').result).failure,
          isNull,
        );
      },
    );
  }

  for (final status in <int?>[null, 1]) {
    test('nonzero/missing status fails safely: $status', () async {
      final h = ChannelHarness();
      addTearDown(h.dispose);
      await h.client.authenticated;
      h.onOpen = (_) => h.accept();
      h.onRequest = (_) {
        h.send(
          SSH_Message_Channel_Success(
            recipientChannel: h.opens.last.senderChannel,
          ),
        );
        h.finish(status: status);
      };
      expect(
        (await h.client.startBoundedExec('synthetic').result).failure,
        SSHBoundedExecFailure.invalidResponse,
      );
    });
  }
}
