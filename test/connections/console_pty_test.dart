import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'monitoring_channel_test.dart' show ChannelHarness, turns;

void main() {
  late ChannelHarness h;
  setUp(() async {
    h = ChannelHarness();
    await h.client.authenticated;
  });
  tearDown(() async {
    await h.dispose();
  });

  SSHOwnedPtyOperation open({Duration? timeout}) => h.client.startOwnedPty(
    SSHOwnedPtyOptions(
      timeout: timeout ?? const Duration(seconds: 15),
      onData: (_) {},
      send: (payload, guard, committed, wait) async {
        await h.client.waitForOwnedPacketReady();
        guard();
        if (!h.client.trySendOwnedPacket(payload)) throw StateError('rekey');
        committed();
      },
    ),
  );

  test(
    'cancelled pending open never sends PTY or shell after late confirmation',
    () async {
      final operation = open();
      final failed = expectLater(
        operation.opened,
        throwsA(isA<SSHOwnedPtyError>()),
      );
      await turns();
      operation.cancel();
      h.accept();
      await failed;
      await turns();
      expect(h.requests, isEmpty);
      expect(h.client.isClosed, isFalse);
    },
  );

  test('PTY ack precedes shell and input uses that channel', () async {
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) => h.send(
      SSH_Message_Channel_Success(recipientChannel: h.opens.last.senderChannel),
    );
    final operation = open();
    final session = await operation.opened;
    expect(h.requests.map((r) => r.requestType), ['pty-req', 'shell']);
    final result = await session.sendGuardedData(
      Uint8List.fromList(utf8.encode('echo ok\r')),
      guard: () {},
      cancellation: SSHOwnedPtyCancellation(),
    );
    expect(result.acceptedBytes, 8);
    expect(result.status, SSHOwnedWriteStatus.complete);
    expect(h.packets, contains(94));
    session.abort();
  });

  test('PTY refusal does not request fallback shell', () async {
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) => h.send(
      SSH_Message_Channel_Failure(recipientChannel: h.opens.last.senderChannel),
    );
    final operation = open();
    await expectLater(operation.opened, throwsA(isA<SSHOwnedPtyError>()));
    expect(h.requests.map((r) => r.requestType), ['pty-req']);
    expect(h.client.isClosed, isFalse);
  });
  test('one input deadline decreases across fragments and blocks an expired next packet', () async {
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) => h.send(
      SSH_Message_Channel_Success(recipientChannel: h.opens.last.senderChannel),
    );
    var now = Duration.zero;
    final remaining = <Duration>[];
    final operation = h.client.startOwnedPty(
      SSHOwnedPtyOptions(
        onData: (_) {},
        monotonicNow: () => now,
        send: (payload, guard, committed, wait) async {
          guard();
          if (payload.first == 94) {
            remaining.add(wait.remaining());
            if (remaining.length == 2) now = const Duration(seconds: 16);
            guard();
          }
          expect(h.client.trySendOwnedPacket(payload), true);
          committed();
          if (payload.first == 94 && remaining.length == 1)
            now = const Duration(seconds: 14);
        },
      ),
    );
    final session = await operation.opened;
    final outcome = await session.sendGuardedData(
      Uint8List(65536),
      guard: () {},
      cancellation: SSHOwnedPtyCancellation(),
    );
    expect(remaining, [
      const Duration(seconds: 15),
      const Duration(seconds: 1),
    ]);
    expect(outcome.acceptedBytes, 32768);
    expect(outcome.status, SSHOwnedWriteStatus.outcomeUnknown);
    expect(h.packets.where((p) => p == 94).length, 1);
    session.abort();
  });

  test('zero remote packet size rejects PTY before shell or DATA', () async {
    h.onOpen = (request) => h.send(
      SSH_Message_Channel_Confirmation(
        recipientChannel: request.senderChannel,
        senderChannel: 7,
        initialWindowSize: 65536,
        maximumPacketSize: 0,
        data: Uint8List(0),
      ),
    );
    await expectLater(open().opened, throwsA(isA<SSHOwnedPtyError>()));
    await turns();
    expect(h.requests, isEmpty);
    expect(h.packets.where((p) => p == 94), isEmpty);
    expect(h.client.isClosed, isFalse);
  });

  test('timeout retires open without closing shared SSH', () async {
    final operation = open(timeout: const Duration(milliseconds: 20));
    await expectLater(operation.opened, throwsA(isA<SSHOwnedPtyError>()));
    expect(h.client.isClosed, isFalse);
    h.accept();
    await turns();
    expect(h.requests, isEmpty);
  });

  test(
    'zero remote window input is cancelled without sending a fragment',
    () async {
      h.onOpen = (request) => h.send(
        SSH_Message_Channel_Confirmation(
          recipientChannel: request.senderChannel,
          senderChannel: 7,
          initialWindowSize: 0,
          maximumPacketSize: 32768,
          data: Uint8List(0),
        ),
      );
      h.onRequest = (_) => h.send(
        SSH_Message_Channel_Success(
          recipientChannel: h.opens.last.senderChannel,
        ),
      );
      final session = await open().opened;
      final cancellation = SSHOwnedPtyCancellation();
      final writing = session.sendGuardedData(
        Uint8List.fromList([97]),
        guard: () {},
        cancellation: cancellation,
      );
      await turns();
      cancellation.cancel();
      final result = await writing;
      expect(result.acceptedBytes, 0);
      expect(h.packets.where((p) => p == 94), isEmpty);
      expect(h.client.isClosed, isFalse);
      session.abort();
    },
  );

  test(
    'retired protocol slots are capped and released by open failure',
    () async {
      for (var i = 0; i < 16; i++) {
        final operation = open();
        await turns();
        operation.cancel();
      }
      expect(() => open(), throwsA(isA<SSHOwnedPtyError>()));
      for (final request in List.of(h.opens)) {
        h.send(
          SSH_Message_Channel_Open_Failure(
            recipientChannel: request.senderChannel,
            reasonCode: 1,
            description: 'synthetic refusal',
            languageTag: '',
          ),
        );
      }
      await turns();
      final next = open();
      await turns();
      expect(h.opens.length, 17);
      next.cancel();
    },
  );

  test(
    'guarded packet refuses rekey without buffering or advancing cipher',
    () async {
      final rekey = h.client.rekey();
      expect(h.client.ownedPacketBlocked, isTrue);
      final payload = SSH_Message_Channel_Data(
        recipientChannel: 7,
        data: Uint8List.fromList([97]),
      ).encode();
      expect(h.client.trySendOwnedPacket(payload), isFalse);
      await rekey;
      await h.client.ping();
      expect(h.packets.where((p) => p == 94), isEmpty);
      expect(h.client.isClosed, isFalse);
    },
  );
}
