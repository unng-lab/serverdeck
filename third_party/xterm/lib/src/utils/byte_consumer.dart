import 'dart:collection';
import 'package:xterm/src/core/terminal_limit.dart';

class ByteConsumer {
  final _queue = ListQueue<List<int>>();

  final _consumed = ListQueue<List<int>>();

  var _currentOffset = 0;

  var _length = 0;

  var _totalConsumed = 0;
  int totalConsumedBytes = 0;
  int tokenStartBytes = 0;
  final _byteWidths = ListQueue<int>();

  void add(String data) {
    if (data.isEmpty) return;
    final runes = data.runes.toList(growable: false);
    _queue.addLast(runes);
    _length += runes.length;
  }

  int peek() {
    final data = _queue.first;
    if (_currentOffset < data.length) {
      return data[_currentOffset];
    } else {
      final result = consume();
      rollback();
      return result;
    }
  }

  int consume() {
    final data = _queue.first;

    if (_currentOffset >= data.length) {
      _consumed.add(_queue.removeFirst());
      _currentOffset -= data.length;
      return consume();
    }

    final scalar = data[_currentOffset];
    final width = scalar <= 0x7f
        ? 1
        : scalar <= 0x7ff
            ? 2
            : scalar <= 0xffff
                ? 3
                : 4;
    if (totalConsumedBytes + width - tokenStartBytes > 16384) {
      throw const TerminalLimitException();
    }
    totalConsumedBytes += width;
    _byteWidths.addLast(width);
    _length--;
    _totalConsumed++;
    return data[_currentOffset++];
  }

  /// Rolls back the last [n] call.
  void rollback([int n = 1]) {
    for (var i = 0; i < n; i++) {
      totalConsumedBytes -= _byteWidths.removeLast();
    }
    _currentOffset -= n;
    _totalConsumed -= n;
    _length += n;
    while (_currentOffset < 0) {
      final rollback = _consumed.removeLast();
      _queue.addFirst(rollback);
      _currentOffset += rollback.length;
    }
  }

  /// Rolls back to the state when this consumer had [length] bytes.
  void rollbackTo(int length) {
    rollback(length - _length);
  }

  int get length => _length;

  int get totalConsumed => _totalConsumed;

  bool get isEmpty => _length == 0;

  bool get isNotEmpty => _length != 0;

  /// Unreferences data blocks that have been consumed. After calling this
  /// method, the consumer will not be able to roll back to consumed blocks.
  void unrefConsumedBlocks() {
    _consumed.clear();
    _byteWidths.clear();
  }

  /// Resets the consumer to its initial state.
  void reset() {
    _queue.clear();
    _consumed.clear();
    _byteWidths.clear();
    _currentOffset = 0;
    _totalConsumed = 0;
    totalConsumedBytes = 0;
    tokenStartBytes = 0;
    _length = 0;
  }
}

// void main() {
//   final consumer = ByteConsumer();
//   consumer.add(Uint8List.fromList([1, 2, 3]));
//   consumer.add(Uint8List.fromList([4, 5, 6]));

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }

//   consumer.rollback(5);

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }

//   consumer.rollbackTo(3);

//   while (consumer.isNotEmpty) {
//     print(consumer.consume());
//   }
// }
