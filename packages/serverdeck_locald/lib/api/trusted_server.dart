import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../mcp/router.dart';
import 'operational_auth.dart';
import 'owner_api.dart';

export 'owner_api.dart';

/// Ownership of request interest transfers to the channel, including late
/// replies after its response deadline. Completion is deliberately idempotent.
final class TrustedReply {
  TrustedReply._(
    this.id,
    this.request,
    this.bytes,
    this.closeChannel,
    this.terminal,
  );
  final String id;
  final TrustedSessionRequest request;
  final List<int>? bytes;
  final bool closeChannel;
  final TrustedOpenFailure? terminal;
  void release() => request.complete();
}

/// Fixed format3 server composition. Native2 uses its separate closed codec;
/// both enter the same typed owner/catalog services for their storage generation.
final class TrustedApiServer {
  TrustedApiServer({
    required this.sessions,
    required TrustedMcpAuthority authority,
    required TrustedMcpRouter router,
    required this.readiness,
    TrustedOwnerApi? owner,
  }) : _authority = authority,
       _router = router,
       _owner = owner {
    if (!identical(sessions, router.sessions) ||
        !identical(authority, router.authority)) {
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    }
  }

  /// Authenticated readiness/ping during real storage startup. Domain routes
  /// remain unavailable until the actual same-registry services are attached.
  TrustedApiServer.starting({required this.sessions, required this.readiness});
  final TrustedSessions sessions;
  TrustedMcpAuthority? _authority;
  TrustedMcpRouter? _router;
  TrustedOwnerApi? _owner;
  TrustedMcpAuthority get authority =>
      _authority ?? (throw StateError('NOT_READY'));
  TrustedMcpRouter get router => _router ?? (throw StateError('NOT_READY'));
  TrustedOwnerApi? get owner => _owner;
  bool get isActivated => _authority != null;
  void activate({
    required TrustedMcpAuthority authority,
    required TrustedMcpRouter router,
    required TrustedOwnerApi owner,
  }) {
    if (isActivated ||
        !identical(sessions, router.sessions) ||
        !identical(authority, router.authority))
      throw StateError('NOT_READY');
    _authority = authority;
    _router = router;
    _owner = owner;
  }

  final TrustedReadiness Function() readiness;

  TrustedReadiness _view() {
    final result = readiness();
    if (result.generation != sessions.generation) throw StateError('INTERNAL');
    if (result.state == ReadinessState.ready && !isActivated)
      throw StateError('INTERNAL');
    return result;
  }

  Future<TrustedReply> handle(String channel, List<int> frame) async {
    final envelope = StrictCodec().decode(frame, maxBytes: maxRequestBytes);
    validateRequestEnvelope(envelope);
    final id = envelope['id'] as String,
        session = envelope['sessionId'] as String,
        method = envelope['method'] as String,
        params = envelope['params'] as Map<String, Object?>;
    TrustedSessionRequest? request;
    TrustedOwnerInvocation? invocation;
    var transferred = false;
    var ownerRoute = false;
    TrustedReply reply({
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
      final value = TrustedReply._(id, request!, bytes, close, terminal);
      transferred = true;
      return value;
    }

    try {
      request = sessions.reserve(channel, session, method);
      const builtins = {
        'readiness.get',
        'session.ping',
        'session.close',
        'mcp.close',
        'mcp.open',
        'mcp.invoke',
      };
      if (!builtins.contains(method)) {
        if (request.role != OperationalRole.owner)
          throw StateError('FORBIDDEN');
        ownerRoute = true;
        final view = _view();
        if (view.state != ReadinessState.ready)
          throw StateError(view.toJson()['reason'] as String);
        if (owner?.supports(method) != true) throw StateError('UNSUPPORTED');
        invocation = owner!.prepare(request, method, params, requestId: id);
      }
      try {
        await sessions.completeAdmission(request);
      } catch (_) {
        invocation?.close();
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
          final view = _view();
          if (view.state != ReadinessState.ready) {
            throw StateError(view.toJson()['reason'] as String);
          }
          result = await invocation!.execute();
      }
      return reply(result: result);
    } catch (error) {
      final terminal = request?.openFailure;
      if (terminal != null) return reply(close: true, terminal: terminal);
      if (error is StateError && error.message == 'UNAUTHORIZED') rethrow;
      if (request != null && !request.initialAdmissionProved) {
        invocation?.close();
        request.complete();
        request = null;
      }
      // A denied method still needs an authenticated, bounded publication
      // interest. This does not execute or inspect the denied operation.
      request ??= await sessions.begin(channel, session, 'session.ping');
      final code = error is FormatException
          ? 'VALIDATION'
          : error is SshTransportFailure && ownerRoute
          ? TrustedLocalError.fromTransport(error.code).code
          : error is StateError &&
                (ownerRoute
                    ? TrustedLocalError.codes.contains(error.message)
                    : ErrorCode.values.any(
                        (candidate) => candidate.wireName == error.message,
                      ))
          ? error.message
          : 'INTERNAL';
      return reply(error: TrustedLocalError(code));
    } finally {
      invocation?.close();
      if (!transferred) request?.complete();
    }
  }
}
