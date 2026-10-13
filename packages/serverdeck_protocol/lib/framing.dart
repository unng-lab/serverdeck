import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'codec.dart';
import 'protocol.dart';

typedef ChunkReader = Future<List<int>> Function(Duration deadline);

/// The reader must finish native cancellation before completing with an error.
class FramedReader {
  FramedReader(
    this.readChunk, {
    this.maxBytes = maxRequestBytes,
    this.partialDeadline = rpcDeadline,
    this.idleDeadline = sessionLease,
  }) {
    if (maxBytes < 1 ||
        maxBytes > maxResponseBytes ||
        partialDeadline <= Duration.zero ||
        partialDeadline > rpcDeadline ||
        idleDeadline <= Duration.zero) {
      throw ArgumentError('INVALID_FRAME_LIMIT');
    }
    _decoder = FrameDecoder(maxBytes: maxBytes);
  }
  final ChunkReader readChunk;
  final int maxBytes;
  final Duration partialDeadline, idleDeadline;
  late final FrameDecoder _decoder;
  final _clock = Stopwatch()..start();
  final _ready = Queue<Uint8List>();
  int? _partialStarted;
  bool _busy = false, _failed = false;

  Duration _remaining() => Duration(
    microseconds:
        partialDeadline.inMicroseconds -
        (_clock.elapsedMicroseconds - _partialStarted!),
  );

  Future<Uint8List> readFrame() async {
    if (_failed || _busy) throw StateError('FRAME_READER_UNAVAILABLE');
    _busy = true;
    try {
      while (true) {
        if (_partialStarted != null && _remaining() <= Duration.zero) {
          throw TimeoutException('PARTIAL_FRAME_TIMEOUT');
        }
        if (_ready.isNotEmpty) return _ready.removeFirst();
        final deadline = _partialStarted == null ? idleDeadline : _remaining();
        final bytes = await readChunk(deadline);
        // Completion at the boundary does not extend the original deadline.
        if (_partialStarted != null && _remaining() <= Duration.zero) {
          throw TimeoutException('PARTIAL_FRAME_TIMEOUT');
        }
        if (bytes.isEmpty) throw StateError('CHANNEL_CLOSED');
        if (bytes.length > 64 * 1024 || bytes.any((b) => b < 0 || b > 255)) {
          throw const FormatException('INVALID_FRAME');
        }
        final frames = _decoder.add(bytes);
        if (_decoder.hasPartialFrame) {
          if (_partialStarted == null || frames.isNotEmpty) {
            _partialStarted = _clock.elapsedMicroseconds;
          }
        } else {
          _partialStarted = null;
        }
        _ready.addAll(frames);
      }
    } catch (_) {
      _failed = true;
      _ready.clear();
      rethrow;
    } finally {
      _busy = false;
    }
  }
}
