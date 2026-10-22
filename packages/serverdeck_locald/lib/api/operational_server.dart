import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../mcp/router.dart';
import 'operational_auth.dart';

/// Trusted owner adapters use the common coordinator; they cannot mint a role.
abstract interface class OperationalOwnerApi {
  bool supports(String method);
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  });
}

/// Prepared by trusted adapter code after the retained native role gate; no
/// callback, role or invocation token can be supplied through a wire payload.
final class OperationalOwnerInvocation {
  OperationalOwnerInvocation(
    this.request,
    this._effect, {
    void Function()? onClose,
  }) : _onClose = onClose;
  final OperationalSessionRequest request;
  final Future<Map<String, Object?>> Function() _effect;
  final void Function()? _onClose;
  Future<Map<String, Object?>>? _work;
  bool _closed = false;

  Future<Map<String, Object?>> execute() {
    try {
      if (_closed) throw StateError('SERVICE_UNAVAILABLE');
      if (!request.initialAdmissionProved ||
          request.role != OperationalRole.owner)
        throw StateError('FORBIDDEN');
      request.rpcRemaining;
      return _work ??= Future.sync(_effect);
    } catch (error, stack) {
      return Future.error(error, stack);
    }
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _onClose?.call();
  }
}

extension OperationalOwnerDispatch on OperationalOwnerApi {
  Future<Map<String, Object?>> dispatch(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) async {
    if (!request.initialAdmissionProved) throw StateError('FORBIDDEN');
    final invocation = prepare(request, method, params, requestId: requestId);
    try {
      return await invocation.execute();
    } finally {
      invocation.close();
    }
  }
}

final class OperationalOwnerApiGroup implements OperationalOwnerApi {
  OperationalOwnerApiGroup(Iterable<OperationalOwnerApi> adapters)
    : _adapters = List.unmodifiable(adapters);
  final List<OperationalOwnerApi> _adapters;
  @override
  bool supports(String method) => _adapters.any((a) => a.supports(method));
  @override
  OperationalOwnerInvocation prepare(
    OperationalSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    if (request.role != OperationalRole.owner || request.method != method)
      throw StateError('FORBIDDEN');
    final matches = _adapters.where((a) => a.supports(method)).toList();
    if (matches.isEmpty) throw StateError('UNSUPPORTED');
    if (matches.length != 1) throw StateError('INTERNAL');
    return matches.single.prepare(
      request,
      method,
      params,
      requestId: requestId,
    );
  }
}

/// Ownership of request interest transfers to the channel, including late
/// replies after its response deadline. Completion is deliberately idempotent.
final class OperationalReply {
  OperationalReply._(
    this.id,
    this.request,
    this.bytes,
    this.closeChannel,
    this.terminal,
  );
  final String id;
  final OperationalSessionRequest request;
  final List<int>? bytes;
  final bool closeChannel;
  final OperationalOpenFailure? terminal;
  void release() => request.complete();
}

final class OperationalApiServer {
  OperationalApiServer({
    required this.sessions,
    required this.authority,
    required this.router,
    required this.readiness,
    this.owner,
  }) {
    if (!identical(sessions, router.sessions) ||
        !identical(authority, router.authority)) {
      throw ArgumentError('INVALID_CHANNEL_CONFIGURATION');
    }
  }
  final OperationalSessions sessions;
  final OperationalMcpAuthority authority;
  final McpRouter router;
  final OperationalReadiness Function() readiness;
  final OperationalOwnerApi? owner;

  OperationalReadiness _view() {
    final result = readiness();
    if (result.generation != sessions.generation) throw StateError('INTERNAL');
    return result;
  }

  Future<OperationalReply> handle(String channel, List<int> frame) async {
    final envelope = StrictCodec().decode(frame, maxBytes: maxRequestBytes);
    validateRequestEnvelope(envelope);
    final id = envelope['id'] as String,
        session = envelope['sessionId'] as String,
        method = envelope['method'] as String,
        params = envelope['params'] as Map<String, Object?>;
    OperationalSessionRequest? request;
    OperationalOwnerInvocation? invocation;
    var transferred = false;
    OperationalReply reply({
      Map<String, Object?>? result,
      LocalError? error,
      bool close = false,
      OperationalOpenFailure? terminal,
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
      final value = OperationalReply._(id, request!, bytes, close, terminal);
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
        if (owner?.supports(method) != true) throw StateError('UNSUPPORTED');
        final view = _view();
        if (view.state != ReadinessState.ready)
          throw StateError(view.toJson()['reason'] as String);
        invocation = owner!.prepare(request, method, params, requestId: id);
      }
      try {
        await sessions.completeAdmission(request);
      } catch (_) {
        invocation?.close();
        request = null;
        rethrow;
      }
      request.rpcRemaining;
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
      var code = error is FormatException
          ? ErrorCode.validation
          : ErrorCode.internal;
      if (error is StateError) {
        for (final candidate in ErrorCode.values) {
          if (candidate.wireName == error.message) code = candidate;
        }
      }
      return reply(error: LocalError(code));
    } finally {
      invocation?.close();
      if (!transferred) request?.complete();
    }
  }
}
