import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../mcp/router.dart';
import '../hosting/sessions.dart';

/// Ownership of request interest transfers to the channel, including late
/// replies after its response deadline. Completion is deliberately idempotent.
final class McpReply {
  McpReply._(
    this.id,
    this.request,
    this.bytes,
    this.closeChannel,
    this.terminal,
  );
  final String id;
  final SessionRequest request;
  final List<int>? bytes;
  final bool closeChannel;
  final TrustedOpenFailure? terminal;
  void release() => request.complete();
}

/// Target typed server composition. Domain routes share one store and registry.
final class McpApiServer {
  McpApiServer({
    required this.sessions,
    required TrustedMcpAuthority authority,
    required TrustedMcpRouter router,
    required this.readiness,
  }) : _authority = authority,
       _router = router {
    if (!identical(sessions, router.sessions) ||
        !identical(authority, router.authority)) {
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    }
  }

  /// Authenticated readiness/ping during real storage startup. Domain routes
  /// remain unavailable until the actual same-registry services are attached.
  McpApiServer.starting({required this.sessions, required this.readiness});
  final EngineSessions sessions;
  TrustedMcpAuthority? _authority;
  TrustedMcpRouter? _router;
  TrustedMcpAuthority get authority =>
      _authority ?? (throw StateError('NOT_READY'));
  TrustedMcpRouter get router => _router ?? (throw StateError('NOT_READY'));
  bool get isActivated => _authority != null;
  void activate({
    required TrustedMcpAuthority authority,
    required TrustedMcpRouter router,
  }) {
    if (isActivated ||
        !identical(sessions, router.sessions) ||
        !identical(authority, router.authority))
      throw StateError('NOT_READY');
    _authority = authority;
    _router = router;
  }

  final TrustedReadiness Function() readiness;

  TrustedReadiness _view() {
    final result = readiness();
    if (result.generation != sessions.generation) throw StateError('INTERNAL');
    if (result.state == ReadinessState.ready && !isActivated)
      throw StateError('INTERNAL');
    return result;
  }

  Future<McpReply> handle(String channel, List<int> frame) async {
    final envelope = StrictCodec().decode(frame, maxBytes: maxRequestBytes);
    validateRequestEnvelope(envelope);
    final id = envelope['id'] as String,
        session = envelope['sessionId'] as String,
        method = envelope['method'] as String,
        params = envelope['params'] as Map<String, Object?>;
    SessionRequest? request;
    var transferred = false;
    McpReply reply({
      Map<String, Object?>? result,
      TrustedLocalError? error,
      bool close = false,
      TrustedOpenFailure? terminal,
    }) {
      List<int>? bytes;
      try {
        bytes = terminal == null
            ? List<int>.unmodifiable(
                encodeMcpMessage({
                  'v': 1,
                  'id': id,
                  'generation': sessions.generation,
                  if (error != null)
                    'error': error.toJson()
                  else
                    'result': result!,
                }),
              )
            : null;
      } catch (_) {
        throw StateError('INTERNAL');
      }
      final value = McpReply._(id, request!, bytes, close, terminal);
      transferred = true;
      return value;
    }

    try {
      request = sessions.reserve(channel, session, method);
      try {
        await sessions.completeAdmission(request);
      } catch (_) {
        request = null;
        rethrow;
      }
      request.rpcBudgetRemaining;
      Map<String, Object?> result;
      switch (method) {
        case 'readiness.get':
          requireFields(params, {});
          result = _view().toJson();
        case 'session.ping':
          requireFields(params, {});
          result = {'leaseSeconds': 60};
        case 'session.close' || 'mcp.close':
          requireFields(params, {});
          return reply(result: {'closed': true}, close: true);
        case 'mcp.open':
          result = (await request.openGrant(authority, params)).toJson();
        case 'mcp.invoke':
          result = (await router.invoke(request, params)).toJson();
        default:
          throw StateError('FORBIDDEN');
      }
      return reply(result: result);
    } catch (error) {
      final terminal = request?.openFailure;
      if (terminal != null) return reply(close: true, terminal: terminal);
      if (error is StateError && error.message == 'UNAUTHORIZED') rethrow;
      if (request != null && !request.initialAdmissionProved) {
        request.complete();
        request = null;
      }
      // A denied method still needs an authenticated, bounded publication
      // interest. This does not execute or inspect the denied operation.
      request ??= await sessions.begin(channel, session, 'session.ping');
      final code = error is FormatException
          ? 'VALIDATION'
          : error is StateError &&
                ErrorCode.values.any(
                  (candidate) => candidate.wireName == error.message,
                )
          ? error.message
          : 'INTERNAL';
      return reply(error: TrustedLocalError(code));
    } finally {
      if (!transferred) request?.complete();
    }
  }
}
