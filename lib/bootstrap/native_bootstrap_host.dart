import 'dart:isolate';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';

import 'local_api_client.dart';
import 'native_client_transport.dart';

class NativeBootstrapHost {
  NativeBootstrapHost() {
    client = LocalApiClient(connect: _endpoint);
  }
  late final LocalApiClient client;
  ClientBootstrapEnvironment? _environment;
  OwnedLocaldChild? _child;
  bool _disposed = false;
  Future<void>? _ensuring, _closing;

  Future<void> prepare() async {
    try {
      _environment = await Isolate.run(ClientBootstrapEnvironment.verify);
      if (_disposed)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
    } on Object catch (error) {
      throw _safe(error);
    }
  }

  Future<void> ensureService() =>
      _ensuring ??= _ensure().whenComplete(() => _ensuring = null);

  Future<void> _ensure() async {
    if (_disposed) return;
    try {
      await client.connect();
      return;
    } on LocalApiException catch (error) {
      if (error.code != ErrorCode.serviceUnavailable &&
          error.code != ErrorCode.timeout)
        rethrow;
    }
    final environment = _environment!;
    if (_disposed) return;
    try {
      final child = _child;
      if (child != null) {
        if (await Isolate.run(child.isLive)) return;
        await Isolate.run(child.close);
        _child = null;
      }
      if (_disposed) return;
      _child = await Isolate.run(environment.launch);
    } on Object catch (error) {
      throw _safe(error);
    }
  }

  Future<ClientEndpoint> _endpoint() async {
    final environment = _environment;
    if (environment == null || _disposed)
      throw const LocalApiException(ErrorCode.serviceUnavailable);
    try {
      final descriptor = await Isolate.run(environment.discovery);
      if (descriptor == null)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      final token = descriptor.bootstrapToken;
      try {
        if (_disposed)
          throw const LocalApiException(ErrorCode.serviceUnavailable);
        for (final name in descriptor.pipeNames) {
          try {
            final transport = await NativeClientTransport.open(
              pipeName: name,
              ownerSid: environment.sid,
              imagePath: environment.localdPath,
              imageHash: environment.manifest.sha256['locald.exe']!,
            );
            return ClientEndpoint(
              transport: transport,
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
    } on Object catch (error) {
      throw _safe(error);
    }
  }

  void dispose() => _disposed = true;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    dispose();
    try {
      await _ensuring;
    } on Object {
      /* Monitor is still retired below. */
    }
    final child = _child;
    if (child != null) {
      try {
        await Isolate.run(child.close);
        _child = null;
      } on Object catch (error) {
        throw _safe(error);
      }
    }
  }

  LocalApiException _safe(Object error) {
    if (error is LocalApiException) return error;
    return LocalApiException(
      error is StateError && error.message == 'INCOMPATIBLE'
          ? ErrorCode.incompatible
          : error is StateError && error.message == 'STORAGE_BLOCKED'
          ? ErrorCode.storageBlocked
          : ErrorCode.serviceUnavailable,
    );
  }
}
