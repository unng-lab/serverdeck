import 'dart:async';
import 'dart:isolate';

import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/client_bootstrap.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';

import 'local_gateway.dart';

/// One configured process startup; no reconnect after grant proof or effect
/// submission. Bootstrap retries only discovery and unavailable pipe slots.
final class McpProcessBootstrap {
  McpProcessBootstrap._(this.environment, this.grantId, this._clock);
  final TrustedMcpBootstrapEnvironment environment;
  final String grantId;
  final Stopwatch _clock;
  OwnedLocaldChild? _child;
  TrustedBootstrapClient? _bootstrap;
  LocalMcpGateway? _gateway;
  bool _used = false, _closed = false;
  Future<void>? _closing;

  static Future<McpProcessBootstrap> prepare(
    String appRoot,
    String grantId,
  ) async {
    requireUuid(grantId);
    final clock = Stopwatch()..start();
    return McpProcessBootstrap._(
      await TrustedMcpBootstrapEnvironment.verify(appRoot),
      grantId,
      clock,
    );
  }

  void _live() {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (_clock.elapsed >= const Duration(seconds: 30))
      throw StateError('TIMEOUT');
  }

  Future<LocalMcpGateway> connect() async {
    if (_used) throw StateError('SERVICE_UNAVAILABLE');
    _used = true;
    while (true) {
      _live();
      final descriptor = await Isolate.run(environment.discovery);
      if (descriptor != null) {
        final token = descriptor.bootstrapToken;
        try {
          for (final name in descriptor.pipeNames) {
            _live();
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
            _bootstrap = TrustedBootstrapClient(
              pipe: pipe,
              generation: descriptor.generation,
              token: token,
            );
            _live();
            final session = await _bootstrap!.authenticate();
            _live();
            while (true) {
              final readiness = await session.readinessBeforeGrant();
              _live();
              if (readiness.state == ReadinessState.ready) {
                final files = McpCredentialFiles(
                  localAppData: environment.localAppData,
                  workspaceId: readiness.workspaceId!,
                  ownerSid: environment.sid,
                  custody: McpCredentialCustody(DpapiProtection()),
                );
                await session.openGrant(files, grantId);
                _live();
                _gateway = await LocalMcpGateway.connectTrusted(session);
                _live();
                // The gateway's RPC client now owns the actual session/pipe.
                _bootstrap = null;
                return _gateway!;
              }
              if (readiness.state != ReadinessState.starting &&
                  readiness.state != ReadinessState.recovering)
                throw StateError(
                  readiness.toJson()['reason'] as String? ??
                      'SERVICE_UNAVAILABLE',
                );
              await Future<void>.delayed(const Duration(milliseconds: 100));
              _live();
            }
          }
        } finally {
          token.fillRange(0, token.length, 0);
          descriptor.close();
        }
      }
      if (_child == null) {
        _live();
        _child = await Isolate.run(environment.launch);
        _live();
      } else if (!await Isolate.run(_child!.isLive)) {
        throw StateError('SERVICE_UNAVAILABLE');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    _closed = true;
    _clock.stop();
    try {
      await _gateway?.close();
    } finally {
      try {
        await _bootstrap?.close();
      } finally {
        final child = _child;
        if (child != null) await Isolate.run(child.close);
      }
    }
  }
}
