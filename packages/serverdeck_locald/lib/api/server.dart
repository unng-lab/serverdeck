import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';

import '../profiles/mutation_coordinator.dart';
import 'sessions.dart';

class ApiDispatch {
  ApiDispatch(this.bytes, {this.closeChannel = false});
  final List<int> bytes;
  final bool closeChannel;
}

class ApiServer {
  ApiServer({
    required this.sessions,
    required this.readiness,
    required this.coordinator,
  });
  final SessionRegistry sessions;
  final ReadinessView Function() readiness;
  final MutationCoordinator? Function() coordinator;
  Future<ApiDispatch> handle(String channel, List<int> frame) async {
    final codec = StrictCodec();
    late final Map<String, Object?> envelope;
    try {
      envelope = codec.decode(frame, maxBytes: maxRequestBytes);
      validateRequestEnvelope(envelope);
    } catch (_) {
      throw StateError('INVALID_FRAME');
    }
    final id = envelope['id'] as String,
        sessionId = envelope['sessionId'] as String;
    final name = envelope['method'] as String;
    ApiMethod? method;
    for (final candidate in ApiMethod.values) {
      if (candidate.wireName == name) method = candidate;
    }
    SessionRequest? pending;
    try {
      pending = sessions.begin(channel, sessionId, method?.capability);
      if (method == null) throw StateError('UNSUPPORTED');
      final state = readiness();
      if (state.generation != sessions.generation) throw StateError('INTERNAL');
      MutationCoordinator? backend;
      if (method.requiresReady) {
        if (state.state != ReadinessState.ready) {
          throw StateError(switch (state.state) {
            ReadinessState.storageBlocked => 'STORAGE_BLOCKED',
            ReadinessState.incompatible => 'INCOMPATIBLE',
            _ => 'NOT_READY',
          });
        }
        if (state.workspaceId == null) throw StateError('INTERNAL');
        backend = coordinator();
        if (backend == null) throw StateError('INTERNAL');
      }
      final params = envelope['params'] as Map<String, Object?>;
      validateMethodShape(name, params);
      Map<String, Object?> result;
      var close = false;
      switch (method) {
        case ApiMethod.readinessGet:
          var current = state;
          if (state.state == ReadinessState.ready) {
            try {
              final live = coordinator();
              if (live == null) throw StateError('INTERNAL');
              live.getSettings();
            } on StateError catch (error) {
              if (error.message != 'STORAGE_BLOCKED') rethrow;
              current = ReadinessView(
                state: ReadinessState.storageBlocked,
                reason: ErrorCode.storageBlocked,
                workspaceId: state.workspaceId,
                generation: state.generation,
              );
            }
          }
          result = current.toJson();
        case ApiMethod.sessionPing:
          result = {'leaseSeconds': 60};
        case ApiMethod.sessionClose:
          result = {'closed': true};
          close = true;
          sessions.disconnect(channel);
        case ApiMethod.profilesList:
          result = backend!.listProfiles().toJson();
        case ApiMethod.profilesGet:
          requireUuid(params['profileId']);
          result = backend!.getProfile(params['profileId'] as String).toJson();
        case ApiMethod.settingsGet:
          result = backend!.getSettings().toJson();
        case ApiMethod.mutationsGet:
          requireUuid(params['requestId']);
          if (params['requestId'] == id)
            throw const FormatException('VALIDATION');
          result = backend!.status(params['requestId'] as String).toJson();
        case ApiMethod.mutationsRecent:
          final limit = params['limit'] ?? 20;
          if (limit is! int || limit < 1 || limit > 100)
            throw const FormatException('VALIDATION');
          result = backend!.recent(limit: limit).toJson();
        case ApiMethod.profilesCreate ||
            ApiMethod.profilesUpdate ||
            ApiMethod.profilesDelete ||
            ApiMethod.settingsUpdate:
          // submit registers canonical input/inflight synchronously before this
          // first await; status cannot report not-found for an admitted frame.
          result = (await backend!.submit(
            id,
            method,
            params,
            requester: sessionId,
          )).toJson();
      }
      try {
        validateMethodResult(name, result);
      } catch (_) {
        throw StateError('INTERNAL');
      }
      try {
        return ApiDispatch(
          codec.encode(
            ApiResponse.success(
              id: id,
              generation: sessions.generation,
              result: result,
            ).toJson(),
            maxBytes: maxResponseBytes,
          ),
          closeChannel: close,
        );
      } on FormatException {
        throw StateError('RESOURCE_LIMIT');
      }
    } catch (error) {
      if (error is StateError && error.message == 'UNAUTHORIZED')
        throw StateError('UNAUTHORIZED');
      var code = ErrorCode.internal;
      if (error is FormatException) code = ErrorCode.validation;
      if (error is StateError) {
        for (final candidate in ErrorCode.values) {
          if (candidate.wireName == error.message) code = candidate;
        }
      }
      return ApiDispatch(
        codec.encode(
          ApiResponse.failure(
            id: id,
            generation: sessions.generation,
            error: LocalError(code).toJson(),
          ).toJson(),
          maxBytes: maxResponseBytes,
        ),
      );
    } finally {
      pending?.complete();
    }
  }
}
