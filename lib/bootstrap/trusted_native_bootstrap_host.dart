import 'dart:isolate';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';

import 'local_api_client.dart';

/// Owns only verified bootstrap metadata and a retained child handle. Workspace
/// storage and SSH credentials stay inside locald.
final class TrustedNativeBootstrapHost {
  TrustedNativeBootstrapHost() {
    client = LocalApiClient.trusted(connect: _connect);
  }
  late final LocalApiClient client;
  TrustedClientBootstrapEnvironment? _environment;
  OwnedLocaldChild? _child;
  Future<void>? _ensuring, _closing;
  bool _disposed = false;

  Future<void> prepare() async {
    try {
      final environment = await Isolate.run(
        TrustedClientBootstrapEnvironment.verify,
      );
      if (_disposed) throw StateError('SERVICE_UNAVAILABLE');
      _environment = environment;
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
    if (_disposed) return;
    final environment = _environment;
    if (environment == null) throw _safe(StateError('SERVICE_UNAVAILABLE'));
    try {
      final child = _child;
      if (child != null) {
        if (await Isolate.run(child.isLive)) return;
        await Isolate.run(child.close);
        _child = null;
      }
      if (!_disposed) _child = await Isolate.run(environment.launch);
    } on Object catch (error) {
      throw _safe(error);
    }
  }

  Future<(TrustedApiClient, String)> _connect() async {
    final environment = _environment;
    if (environment == null || _disposed)
      throw _safe(StateError('SERVICE_UNAVAILABLE'));
    try {
      final descriptor = await Isolate.run(environment.discovery);
      if (descriptor == null) throw StateError('SERVICE_UNAVAILABLE');
      final token = descriptor.bootstrapToken;
      try {
        for (final name in descriptor.pipeNames) {
          if (_disposed) throw StateError('SERVICE_UNAVAILABLE');
          PipeWorker pipe;
          try {
            pipe = await PipeWorker.openTrustedClient(
              name,
              environment.sid,
              environment.bundle.manifest.appRoot,
            );
          } on StateError catch (error) {
            if (error.message != 'SERVICE_UNAVAILABLE') rethrow;
            continue;
          }
          final bootstrap = TrustedBootstrapClient(
            pipe: pipe,
            generation: descriptor.generation,
            token: token,
          );
          try {
            final session = await bootstrap.authenticate();
            if (_disposed) throw StateError('SERVICE_UNAVAILABLE');
            return (TrustedApiClient(session), descriptor.generation);
          } on Object {
            await bootstrap.close();
            rethrow;
          }
        }
        throw StateError('SERVICE_UNAVAILABLE');
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
      /* Child handle still retires below. */
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
    final code = error is StateError ? error.message : null;
    return LocalApiException(
      ErrorCode.values.where((value) => value.wireName == code).firstOrNull ??
          ErrorCode.serviceUnavailable,
    );
  }
}
