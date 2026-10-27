import 'dart:typed_data';

import 'package:serverdeck_windows/pipe_worker.dart';

import 'local_api_client.dart';

class NativeClientTransport implements ClientTransport {
  NativeClientTransport._(
    this._pipe,
    this.ownerSid,
    this.imagePath,
    this.imageHash,
  );
  final PipeWorker _pipe;
  final String ownerSid, imagePath, imageHash;
  static Future<NativeClientTransport> open({
    required String pipeName,
    required String ownerSid,
    required String imagePath,
    required String imageHash,
  }) async => NativeClientTransport._(
    await PipeWorker.openClient(pipeName, ownerSid),
    ownerSid,
    imagePath,
    imageHash,
  );
  @override
  Future<void> verifyPeer() => _pipe.verifyPeer(ownerSid, imagePath, imageHash);
  @override
  Future<Uint8List> read(int count, Duration deadline) =>
      _pipe.read(count: count, deadline: deadline);
  @override
  Future<void> write(List<int> bytes, Duration deadline) =>
      _pipe.write(bytes, deadline: deadline);
  @override
  Future<void> close() => _pipe.close();
}
