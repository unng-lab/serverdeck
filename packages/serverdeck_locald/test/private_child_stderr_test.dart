import 'dart:async';

import 'package:test/test.dart';

import 'support/private_child_stderr.dart';

void main() {
  test(
    'unterminated stderr cancels once and reuses its drain deadline',
    () async {
      var cancelled = 0;
      var forwarded = 0;
      final stream = StreamController<List<int>>(
        sync: true,
        onCancel: () => cancelled++,
      );
      final capture = PrivateChildStderr(stream.stream, (_) => forwarded++);
      stream.add([1, 2, 3]);
      final draining = capture.drain(timeout: const Duration(milliseconds: 20));
      await expectLater(draining, throwsA(isA<TimeoutException>()));
      expect(cancelled, 1);
      expect(identical(draining, capture.drain()), true);
      await expectLater(capture.drain(), throwsA(isA<TimeoutException>()));
      stream.add([4]);
      expect(forwarded, 1);
      await stream.close();
    },
  );

  test(
    'captures bounded prefix while forwarding the entire private stream',
    () async {
      final stream = StreamController<List<int>>(sync: true);
      var forwarded = 0;
      final capture = PrivateChildStderr(
        stream.stream,
        (chunk) => forwarded += chunk.length,
      );
      stream.add(
        List<int>.filled(PrivateChildStderr.maximumCapturedBytes + 8, 65),
      );
      await stream.close();
      final bytes = await capture.drain();
      expect(bytes, hasLength(PrivateChildStderr.maximumCapturedBytes));
      expect(bytes.every((byte) => byte == 65), true);
      expect(forwarded, PrivateChildStderr.maximumCapturedBytes + 8);
    },
  );
}
