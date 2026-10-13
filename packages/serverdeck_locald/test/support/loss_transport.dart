import 'dart:typed_data';

import 'package:serverdeck_protocol/codec.dart';

import '../../../../lib/bootstrap/local_api_client.dart';

/// Acceptance-only frame loss on an authenticated, verified native transport.
/// No production entry imports this helper or interprets its controls.
class LossTransport implements ClientTransport {
  LossTransport(this.inner);
  final ClientTransport inner;
  String? dropReplyId, holdRequestId;
  String? dropNextMethod, holdNextMethod;
  bool replyDropped = false, requestHeld = false, lateOriginalDelivered = false;
  Uint8List? _held;
  Uint8List _buffer = Uint8List(0);
  int _offset = 0;

  @override
  Future<void> verifyPeer() => inner.verifyPeer();

  @override
  Future<void> write(List<int> bytes, Duration deadline) async {
    final frame = Uint8List.fromList(bytes);
    try {
      final length = ByteData.sublistView(frame).getUint32(0, Endian.little);
      if (length != frame.length - 4) throw StateError('FIXTURE_FRAME_INVALID');
      final value = StrictCodec().decode(Uint8List.sublistView(frame, 4));
      if (dropNextMethod != null && value['method'] == dropNextMethod) {
        dropReplyId = value['id'] as String;
        dropNextMethod = null;
      }
      if (holdNextMethod != null && value['method'] == holdNextMethod) {
        holdRequestId = value['id'] as String;
        holdNextMethod = null;
      }
      if (value['id'] == holdRequestId && holdRequestId != null) {
        if (!requestHeld) {
          _held = Uint8List.fromList(frame);
          requestHeld = true;
          return;
        }
        final original = _held;
        if (original != null) {
          // Deliver explicit retry first, then the delayed identical original.
          await inner.write([...frame, ...original], deadline);
          original.fillRange(0, original.length, 0);
          _held = null;
          lateOriginalDelivered = true;
          return;
        }
      }
      await inner.write(frame, deadline);
    } finally {
      frame.fillRange(0, frame.length, 0);
    }
  }

  @override
  Future<Uint8List> read(int count, Duration deadline) async {
    final watch = Stopwatch()..start();
    Future<Uint8List> exact(int length) async {
      final bytes = Uint8List(length);
      var offset = 0;
      while (offset < length) {
        final remaining = deadline - watch.elapsed;
        if (remaining <= Duration.zero) throw StateError('TIMEOUT');
        final part = await inner.read(
          (length - offset).clamp(1, 65536),
          remaining,
        );
        if (part.isEmpty) throw StateError('SERVICE_UNAVAILABLE');
        bytes.setRange(offset, offset + part.length, part);
        offset += part.length;
      }
      return bytes;
    }

    while (_offset == _buffer.length) {
      _buffer.fillRange(0, _buffer.length, 0);
      final header = await exact(4);
      final length = ByteData.sublistView(header).getUint32(0, Endian.little);
      if (length <= 0 || length > 8 * 1024 * 1024) {
        throw StateError('FIXTURE_FRAME_INVALID');
      }
      final body = await exact(length);
      final value = StrictCodec().decode(body, maxBytes: 8 * 1024 * 1024);
      if (!replyDropped && dropReplyId != null && value['id'] == dropReplyId) {
        replyDropped = true;
        body.fillRange(0, body.length, 0);
        continue;
      }
      _buffer = Uint8List.fromList([...header, ...body]);
      body.fillRange(0, body.length, 0);
      _offset = 0;
    }
    final end = (_offset + count).clamp(0, _buffer.length);
    final result = Uint8List.fromList(_buffer.sublist(_offset, end));
    _offset = end;
    return result;
  }

  @override
  Future<void> close() async {
    try {
      await inner.close();
    } finally {
      _held?.fillRange(0, _held!.length, 0);
      _held = null;
      _buffer.fillRange(0, _buffer.length, 0);
    }
  }
}
