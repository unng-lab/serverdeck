import 'dart:async';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySocket implements SSHSocket {
  final incoming = StreamController<Uint8List>();
  final outgoing = StreamController<List<int>>();
  final closed = Completer<void>();
  int sinkRequests = 0;
  @override
  Stream<Uint8List> get stream => incoming.stream;
  @override
  StreamSink<List<int>> get sink {
    sinkRequests++;
    return outgoing.sink;
  }

  @override
  Future<void> get done => closed.future;
  @override
  Future<void> close() async {
    if (!closed.isCompleted) closed.complete();
    await incoming.close();
  }

  @override
  void destroy() => unawaited(close());
  @override
  Future<void> flush() async {}
}

void main() {
  test(
    'chosen password policy rejects missing host verification before I/O',
    () {
      final socket = MemorySocket();
      expect(
        () => SSHClient(
          socket,
          username: 'user',
          onPasswordRequest: () => 'secret',
        ),
        throwsArgumentError,
      );
      expect(socket.sinkRequests, 0);
    },
  );

  for (final invalid in [
    'noMethod',
    'bothMethods',
    'skipSignature',
    'interactive',
    'missingRekeyHook',
  ]) {
    test('strict vendor policy rejects $invalid before transport starts', () {
      final socket = MemorySocket();
      expect(
        () => SSHClient(
          socket,
          username: 'user',
          onVerifyHostKey: (_, _, _) => true,
          onHostKeyChanged: invalid == 'missingRekeyHook' ? null : (_, _, _) {},
          onPasswordRequest: invalid == 'noMethod' ? null : () => 'synthetic',
          identities: invalid == 'bothMethods' ? [] : null,
          disableHostkeyVerification: invalid == 'skipSignature',
          onUserInfoRequest: invalid == 'interactive' ? (_) => [] : null,
        ),
        throwsArgumentError,
      );
      expect(socket.closed.isCompleted, isFalse);
      expect(socket.sinkRequests, 0);
    });
  }

  test(
    'configured password starts only an in-memory transport and closes',
    () async {
      final socket = MemorySocket();
      final sent = <List<int>>[];
      final subscription = socket.outgoing.stream.listen(sent.add);
      final client = SSHClient(
        socket,
        username: 'user',
        onPasswordRequest: () => 'synthetic',
        onVerifyHostKey: (_, _, _) => false,
        onHostKeyChanged: (_, _, _) {},
        keepAliveInterval: null,
      );
      await client.close();
      await client.done;
      await Future<void>.delayed(Duration.zero);
      expect(sent, isNotEmpty);
      expect(socket.closed.isCompleted, isTrue);
      await subscription.cancel();
      await socket.outgoing.close();
    },
  );
}
