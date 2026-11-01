import 'dart:async';

import 'package:serverdeck_engine/mcp/client.dart';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/mcp_connector.dart';

import 'local_gateway.dart';

/// One stdio startup; both configured and unconfigured modes require the same
/// live application connection. No process/store launch or reconnect path.
final class McpProcessBootstrap {
  McpProcessBootstrap({this.grantId}) {
    if (grantId != null) requireUuid(grantId);
  }
  final String? grantId;
  final _connector = WindowsMcpConnector();
  LocalMcpGateway? _gateway;
  Future<LocalMcpGateway>? _connecting;
  Future<void>? _physical, _closing;
  bool _closed = false;
  void _live() {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
  }

  Future<LocalMcpGateway> connect() {
    if (_connecting != null || _closed)
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    final reply = Completer<LocalMcpGateway>(), physical = Completer<void>();
    _connecting = reply.future;
    _physical = physical.future;
    reply.future.ignore();
    final actual = Future<LocalMcpGateway>.sync(() async {
      final client = await _connector.connect();
      _live();
      final readiness = await client.readiness();
      _live();
      if (readiness.state != ReadinessState.ready || !readiness.features.mcp)
        throw StateError('NOT_READY');
      if (grantId != null) {
        await client.openGrant(_connector.credentials(), grantId!);
        _live();
      }
      final gate = await _connector.publicationGate();
      _live();
      _gateway = LocalMcpGateway.attach(client, gate);
      _live();
      return _gateway!;
    });
    actual.then<void>(
      (_) => physical.complete(),
      onError: (Object _, StackTrace __) => physical.complete(),
    );
    actual
        .timeout(const Duration(seconds: 30))
        .then<void>(
          reply.complete,
          onError: (Object e, StackTrace _) {
            close().ignore();
            reply.completeError(
              e is TimeoutException ? StateError('TIMEOUT') : e,
            );
          },
        );
    return reply.future;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    _closed = true;
    final gateway = _gateway?.close();
    gateway?.ignore();
    final native = _connector.close();
    native.ignore();
    () async {
      var clean = true;
      for (final work in [gateway, native, _physical]) {
        try {
          await work;
        } catch (_) {
          clean = false;
        }
      }
      try {
        await _gateway?.close();
      } catch (_) {
        clean = false;
      }
      if (!clean) throw StateError('SERVICE_UNAVAILABLE');
    }().then<void>(
      done.complete,
      onError: (Object _, StackTrace __) =>
          done.completeError(StateError('SERVICE_UNAVAILABLE')),
    );
    return done.future;
  }
}
