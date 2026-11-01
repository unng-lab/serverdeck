import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/platform/mcp_stdio.dart';

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

final class Native {
  final calls = <String>[];
  final reads = <Completer<Object?>>[];
  final writes = <Completer<Object?>>[];
  final diagnostics = <Completer<Object?>>[];
  final frames = <Uint8List>[];
  final closing = Completer<Object?>();
  Object? version = 1;
  Future<Object?> invoke(String method, Object? value) {
    calls.add(method);
    switch (method) {
      case 'attach':
        expect(value, 1);
        return Future.value(version);
      case 'read':
        expect(value, isNull);
        final c = Completer<Object?>();
        reads.add(c);
        return c.future;
      case 'write':
        frames.add(value! as Uint8List);
        final c = Completer<Object?>();
        writes.add(c);
        return c.future;
      case 'diagnostic':
        expect(value, matches(r'^MCP:[A-Z][A-Z0-9_]{0,63}\n$'));
        final c = Completer<Object?>();
        diagnostics.add(c);
        return c.future;
      case 'close':
        return closing.future;
      default:
        throw StateError('UNEXPECTED_UNIT_METHOD');
    }
  }

  Future<void> close(ChannelMcpStdioPort port) async {
    final result = port.close();
    for (final read in reads) {
      if (!read.isCompleted) read.complete(Uint8List(0));
    }
    for (final write in writes) {
      if (!write.isCompleted) write.completeError(StateError('CANCELLED'));
    }
    for (final diagnostic in diagnostics) {
      if (!diagnostic.isCompleted) diagnostic.complete(true);
    }
    if (!closing.isCompleted) closing.complete(true);
    await result;
  }
}

void main() {
  test('late attach stays owned through native close ACK', () async {
    final attach = Completer<Object?>();
    final nativeClose = Completer<Object?>();
    final port = ChannelMcpStdioPort(
      invoke: (method, _) =>
          method == 'attach' ? attach.future : nativeClose.future,
    );
    var closed = false;
    final close = port.close().then((_) => closed = true);
    nativeClose.complete(true);
    await settle();
    expect(closed, isFalse);
    attach.complete(1);
    await close;
    await expectLater(port.ready, throwsStateError);
  });

  test('attach is private versioned and never creates a UI binding', () async {
    final n = Native();
    final port = ChannelMcpStdioPort(invoke: n.invoke);
    await port.ready;
    expect(n.calls, ['attach']);
    await n.close(port);
  });

  test('invalid or failed native attach exposes only a fixed error', () async {
    for (final version in [null, 1.0, 2, '1']) {
      final n = Native()..version = version;
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      await expectLater(port.ready, throwsStateError);
      await n.close(port);
    }
    final port = ChannelMcpStdioPort(
      invoke: (method, _) async {
        if (method == 'close') return true;
        throw StateError('private native exception');
      },
    );
    await expectLater(
      port.ready,
      throwsA(
        isA<StateError>().having((e) => e.message, 'code', 'STDIO_UNAVAILABLE'),
      ),
    );
    await port.close();
  });

  test(
    'one read, pause bounds buffering, resume and EOF stop reading',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      final values = <List<int>>[];
      final sub = port.input.listen(values.add);
      await settle();
      expect(n.reads, hasLength(1));
      sub.pause();
      final buffer = Uint8List.fromList([1, 2]);
      n.reads.single.complete(buffer);
      await settle();
      buffer[0] = 9;
      expect(n.reads, hasLength(1));
      expect(values, isEmpty);
      sub.resume();
      await settle();
      expect(values, [
        [1, 2],
      ]);
      expect(n.reads, hasLength(2));
      n.reads.last.complete(Uint8List(0));
      await sub.asFuture<void>();
      await settle();
      expect(n.reads, hasLength(2));
      await n.close(port);
    },
  );

  test(
    'cancel drops interest; physical close still waits outstanding read',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      final sub = port.input.listen((_) => fail('cancelled input delivered'));
      await settle();
      await sub.cancel();
      var closed = false;
      final close = port.close().then((_) => closed = true);
      n.closing.complete(true);
      await settle();
      expect(closed, isFalse);
      expect(n.calls, ['attach', 'read', 'close']);
      n.reads.single.complete(Uint8List.fromList([5]));
      await close;
      expect(n.reads, hasLength(1));
    },
  );

  test('oversized or malformed input emits fixed error then stops', () async {
    for (final bytes in [
      <int>[1],
      Uint8List(ChannelMcpStdioPort.maxReadBytes + 1),
    ]) {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      final errors = <Object>[];
      final done = Completer<void>();
      port.input.listen(
        (_) => fail('bad input delivered'),
        onError: errors.add,
        onDone: done.complete,
      );
      await settle();
      n.reads.single.complete(bytes);
      await done.future;
      expect(errors, [isA<StateError>()]);
      expect(n.reads, hasLength(1));
      await n.close(port);
    }
  });

  test(
    'write snapshot and slot remain owned until actual native ACK',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      final source = [10, 20];
      var complete = false;
      final written = port.write(source).then((_) => complete = true);
      source[0] = 99;
      await settle();
      expect(n.frames.single, [10, 20]);
      expect(complete, isFalse);
      await expectLater(port.write([30]), throwsStateError);
      expect(n.writes, hasLength(1));
      n.writes.single.complete(true);
      await written;
      expect(n.frames.single, [0, 0]);
      await n.close(port);
    },
  );

  test(
    'writer rejects empty and oversized frames without native dispatch',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      await expectLater(port.write([]), throwsStateError);
      await expectLater(
        port.write(Uint8List(ChannelMcpStdioPort.maxWriteBytes + 1)),
        throwsStateError,
      );
      expect(n.writes, isEmpty);
      await n.close(port);
    },
  );

  test(
    'failed ACK wipes owned buffer and never exposes native errors',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      final written = port.write([4]);
      final checked = expectLater(
        written,
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'code',
            'STDIO_UNAVAILABLE',
          ),
        ),
      );
      await settle();
      n.writes.single.completeError(StateError('private native exception'));
      await checked;
      expect(n.frames.single, [0]);
      await n.close(port);
    },
  );

  test(
    'close sends cancellation immediately but retains actual write',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      final written = port.write([1]);
      await settle();
      var closed = false;
      final close = port.close();
      unawaited(close.then((_) => closed = true));
      expect(identical(close, port.close()), isTrue);
      n.closing.complete(true);
      await settle();
      expect(n.calls.last, 'close');
      expect(closed, isFalse);
      expect(n.frames.single, [1]);
      n.writes.single.complete(true);
      await written;
      await close;
      await expectLater(port.write([2]), throwsStateError);
      expect(n.calls.where((m) => m == 'close'), hasLength(1));
    },
  );

  test(
    'physical close failure is sticky and cannot be retried as success',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      await port.ready;
      final close = port.close();
      final checked = expectLater(close, throwsStateError);
      n.closing.complete(false);
      await checked;
      expect(identical(port.close(), close), isTrue);
      await expectLater(port.close(), throwsStateError);
      expect(n.calls, ['attach', 'close']);
    },
  );

  test(
    'diagnostics are separate fixed codes, one pending and 32 total',
    () async {
      final n = Native();
      final port = ChannelMcpStdioPort(invoke: n.invoke);
      port.diagnostic('raw secret or exception');
      for (var i = 0; i < 34; i++) {
        port.diagnostic('SERVICE_UNAVAILABLE');
        port.diagnostic('TIMEOUT');
        await settle();
        if (n.diagnostics.isNotEmpty && !n.diagnostics.last.isCompleted) {
          n.diagnostics.last.complete(true);
        }
        await port.flushDiagnostics();
        await settle();
      }
      expect(n.diagnostics, hasLength(32));
      expect(n.writes, isEmpty);
      await n.close(port);
    },
  );
}
