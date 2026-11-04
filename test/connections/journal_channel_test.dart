import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/src/message/msg_channel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'monitoring_channel_test.dart' show ChannelHarness;

void main() {
  test('journal opt-in retains bounded stderr/nonzero without changing shared slot', () async {
    final h = ChannelHarness();
    addTearDown(h.dispose);
    await h.client.authenticated;
    h.onOpen = (_) => h.accept();
    h.onRequest = (_) {
      final id = h.opens.last.senderChannel;
      h.send(SSH_Message_Channel_Success(recipientChannel: id));
      h.send(
        SSH_Message_Channel_Extended_Data(
          recipientChannel: id,
          dataTypeCode: 1,
          data: Uint8List.fromList(utf8.encode('Permission denied')),
        ),
      );
      h.finish(status: 43);
    };
    final result = await h.client
        .startBoundedExec('synthetic read', captureStatus: true)
        .result;
    expect(result.failure, isNull);
    expect(result.exitCode, 43);
    expect(utf8.decode(result.stderr), 'Permission denied');
    final ordinary = await h.client
        .startBoundedExec('synthetic monitor')
        .result;
    expect(ordinary.failure, isNotNull);
    expect(ordinary.stderr, isEmpty);
  });
}
