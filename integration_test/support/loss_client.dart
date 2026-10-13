import 'dart:isolate';

import '../../lib/bootstrap/local_api_client.dart';
import '../../lib/bootstrap/native_client_transport.dart';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';

import '../../packages/serverdeck_locald/test/support/loss_transport.dart';

/// Test target composition only. Production host/entry have no loss controls.
class LossClient {
  LossClient() {
    client = LocalApiClient(connect: _connect);
  }
  late final LocalApiClient client;
  late ClientBootstrapEnvironment _environment;
  LossTransport? _transport;
  LossTransport get transport =>
      _transport ?? (throw StateError('FIXTURE_TRANSPORT_MISSING'));
  Future<void> prepare() async {
    _environment = await Isolate.run(ClientBootstrapEnvironment.verify);
  }

  Future<ClientEndpoint> _connect() async {
    final descriptor = await Isolate.run(_environment.discovery);
    if (descriptor == null)
      throw const LocalApiException(ErrorCode.serviceUnavailable);
    final token = descriptor.bootstrapToken;
    try {
      for (final name in descriptor.pipeNames) {
        try {
          final native = await NativeClientTransport.open(
            pipeName: name,
            ownerSid: _environment.sid,
            imagePath: _environment.localdPath,
            imageHash: _environment.manifest.sha256['locald.exe']!,
          );
          final wrapped = LossTransport(native);
          _transport = wrapped;
          return ClientEndpoint(
            transport: wrapped,
            generation: descriptor.generation,
            buildId: descriptor.buildId,
            bootstrapToken: token,
          );
        } on StateError catch (error) {
          if (error.message != 'SERVICE_UNAVAILABLE') rethrow;
        }
      }
      throw const LocalApiException(ErrorCode.serviceUnavailable);
    } finally {
      token.fillRange(0, token.length, 0);
      descriptor.close();
    }
  }
}
