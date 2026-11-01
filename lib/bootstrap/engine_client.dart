import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

export 'package:serverdeck_engine/hosting/in_process_gateway.dart'
    show EngineCallFailure;

typedef CancelDeadline = void Function();
typedef ScheduleDeadline = CancelDeadline Function(Duration, void Function());
CancelDeadline _defaultSchedule(Duration delay, void Function() action) {
  final timer = Timer(delay, action);
  return timer.cancel;
}

String newRequestId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class EngineApiException implements Exception {
  const EngineApiException(this.code, {this.field});
  final ErrorCode code;
  final String? field;
  RetryAdvice get retry => LocalError(code).retry;
  @override
  String toString() => 'EngineApiException: ${code.wireName}';
}

/// The caller retains this intent until save/cancel/recovery is resolved.
class MutationIntent {
  factory MutationIntent(
    ApiMethod method,
    Map<String, Object?> params, {
    String? requestId,
  }) {
    final id = requestId ?? newRequestId();
    try {
      requireUuid(id);
      if (!method.isMutation)
        throw const EngineApiException(ErrorCode.validation);
      return MutationIntent._(
        method,
        id,
        Uint8List.fromList(
          StrictCodec().encode(params, maxBytes: maxRequestBytes),
        ),
      );
    } catch (_) {
      throw const EngineApiException(ErrorCode.validation);
    }
  }
  MutationIntent._(this.method, this.id, this._params);
  final ApiMethod method;
  final String id;
  final Uint8List _params;
  bool _disposed = false;
  Map<String, Object?> _copyParams() {
    if (_disposed) throw const EngineApiException(ErrorCode.validation);
    return StrictCodec().decode(_params);
  }

  void dispose() {
    _disposed = true;
    _params.fillRange(0, _params.length, 0);
  }
}

Object? _freeze(Object? value) => switch (value) {
  Map<String, Object?>() => Map<String, Object?>.unmodifiable(
    value.map((key, item) => MapEntry(key, _freeze(item))),
  ),
  List() => List<Object?>.unmodifiable(value.map(_freeze)),
  _ => value,
};

class ApiReply {
  ApiReply(this.generation, Map<String, Object?> value)
    : result = _freeze(value) as Map<String, Object?>;
  final String generation;
  final Map<String, Object?> result;
}

class ClientSnapshot {
  ClientSnapshot(this.profiles, this.settings);
  final ApiReply profiles, settings;
  String get generation => profiles.generation;
  String get storeRevision => profiles.result['storeRevision'] as String;
}

enum ClientConnectionState { connecting, connected, disconnected, closed }

/// Permanent presentation session over a root-bound gateway. No IPC/bootstrap
/// token, native role selector, reconnect or storage/SSH authority exists here.
final class EngineClient {
  EngineClient(this._gateway);
  final EngineGateway _gateway;
  String get generation => _gateway.generation;
  bool get isClosed => _gateway.isClosed;
  Future<void> get done => _gateway.retired;
  Future<void> close() => _gateway.close();
  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    String? requestId,
  }) async {
    if (isClosed) throw EngineCallFailure('SERVICE_UNAVAILABLE');
    final result = await _gateway.call(
      method,
      params,
      requestId: requestId ?? newRequestId(),
    );
    if (isClosed &&
        !(method == 'session.close' &&
            result.length == 1 &&
            result['closed'] == true))
      throw EngineCallFailure('SERVICE_UNAVAILABLE');
    return captureTrustedMethodResult(method, result);
  }
}

final class EngineApiClient {
  EngineApiClient({
    required Future<EngineGateway> Function() attach,
    required Future<void> Function() detach,
    ScheduleDeadline schedule = _defaultSchedule,
  }) : _attach = attach,
       _detach = detach,
       _schedule = schedule;
  final Future<EngineGateway> Function() _attach;
  final Future<void> Function() _detach;
  final ScheduleDeadline _schedule;
  final _states = StreamController<ClientConnectionState>.broadcast(sync: true);
  final _snapshots = StreamController<ClientSnapshot>.broadcast();
  final _snapshotErrors = StreamController<ErrorCode>.broadcast(sync: true);
  EngineClient? _session;
  Future<EngineClient>? _connecting;
  Future<void>? _refreshing, _closing;
  Future<void> _retiring = Future.value();
  CancelDeadline? _heartbeatTimer, _pollTimer;
  bool _disposed = false, _polling = false, _refreshAgain = false;
  int _snapshotEpoch = 0;
  int? _publishedSnapshotEpoch;
  ClientSnapshot? _snapshot;
  Stream<ClientConnectionState> get states => _states.stream;
  Stream<ClientSnapshot> get snapshots => _snapshots.stream;
  Stream<ErrorCode> get snapshotErrors => _snapshotErrors.stream;
  String? get generation => _session?.generation;
  EngineClient? get controlClient => _session;
  void captureResult(String method, Map<String, Object?> value) {
    captureTrustedMethodResult(method, value);
  }

  Future<void> connect() async {
    await _connected();
  }

  Future<EngineClient> _connected() {
    if (_disposed)
      return Future.error(
        const EngineApiException(ErrorCode.serviceUnavailable),
      );
    final current = _session;
    if (current != null && !current.isClosed) return Future.value(current);
    if (_connecting != null) return _connecting!;
    final done = Completer<EngineClient>();
    _connecting = done.future;
    done.future.ignore();
    _open().then<void>(
      (client) {
        _connecting = null;
        done.complete(client);
      },
      onError: (Object error, StackTrace _) {
        _connecting = null;
        done.completeError(_safe(error));
      },
    );
    return done.future;
  }

  Future<EngineClient> _open() async {
    _states.add(ClientConnectionState.connecting);
    EngineClient? client;
    try {
      await _retiring;
      if (_disposed)
        throw const EngineApiException(ErrorCode.serviceUnavailable);
      client = EngineClient(await _attach());
      if (_disposed || client.isClosed)
        throw const EngineApiException(ErrorCode.serviceUnavailable);
      _session = client;
      final owned = client;
      owned.done
          .then<void>(
            (_) => _failed(owned),
            onError: (Object _, StackTrace __) => _failed(owned),
          )
          .ignore();
      _states.add(ClientConnectionState.connected);
      _heartbeat(owned);
      return owned;
    } catch (error) {
      if (client != null) {
        _retiring = Future<void>.sync(_detach);
        await _retiring;
      }
      if (!_disposed) _states.add(ClientConnectionState.disconnected);
      throw _safe(error);
    }
  }

  void _failed(EngineClient client) {
    if (!identical(client, _session)) return;
    _session = null;
    _heartbeatTimer?.call();
    stopPolling();
    _snapshot = null;
    _retiring = Future<void>.sync(_detach);
    _retiring.ignore();
    if (!_disposed) _states.add(ClientConnectionState.disconnected);
  }

  void _heartbeat(EngineClient client) {
    _heartbeatTimer?.call();
    if (_disposed || !identical(client, _session) || client.isClosed) return;
    _heartbeatTimer = _schedule(heartbeatInterval, () async {
      try {
        await client.call('session.ping', {});
      } catch (error) {
        if (_safe(error).code != ErrorCode.resourceLimit) {
          client.close().ignore();
          _failed(client);
        }
      } finally {
        _heartbeat(client);
      }
    });
  }

  Future<ApiReply> _call(
    ApiMethod method,
    Map<String, Object?> params,
    String id,
  ) async {
    try {
      // Only explicit connect opens a session. An old poll/read continuation
      // may share an already-started attachment, never initiate another one.
      if (_disposed)
        throw const EngineApiException(ErrorCode.serviceUnavailable);
      final client =
          _session ??
          await (_connecting ??
              Future<EngineClient>.error(
                const EngineApiException(ErrorCode.serviceUnavailable),
              ));
      if (client.isClosed)
        throw const EngineApiException(ErrorCode.serviceUnavailable);
      final result = await client.call(method.wireName, params, requestId: id);
      if (_disposed ||
          !identical(client, _session) ||
          client.generation != generation)
        throw const EngineApiException(ErrorCode.serviceUnavailable);
      return ApiReply(client.generation, result);
    } catch (error) {
      throw _safe(error);
    }
  }

  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) {
    if (method.isMutation)
      return Future.error(const EngineApiException(ErrorCode.validation));
    try {
      final bytes = Uint8List.fromList(
        StrictCodec().encode(params, maxBytes: maxRequestBytes),
      );
      late Map<String, Object?> input;
      try {
        input = StrictCodec().decode(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      return _call(method, input, newRequestId());
    } catch (error) {
      return Future.error(_safe(error));
    }
  }

  Future<ApiReply> mutate(MutationIntent intent) async {
    try {
      final result = await _call(
        intent.method,
        intent._copyParams(),
        intent.id,
      );
      if (_polling) _refreshAfterMutation();
      return result;
    } on EngineApiException catch (error) {
      if (_polling && error.code == ErrorCode.revisionConflict)
        _refreshAfterMutation();
      rethrow;
    }
  }

  Future<ApiReply> mutationStatus(MutationIntent intent) =>
      read(ApiMethod.mutationsGet, {'requestId': intent.id});
  void startPolling() {
    if (_disposed) throw const EngineApiException(ErrorCode.serviceUnavailable);
    _polling = true;
    refreshSnapshot().ignore();
    _poll();
  }

  void stopPolling() {
    _polling = false;
    _refreshAgain = false;
    _snapshotEpoch++;
    _pollTimer?.call();
  }

  void _poll() {
    _pollTimer?.call();
    if (_disposed || !_polling) return;
    _pollTimer = _schedule(const Duration(seconds: 2), () {
      if (_disposed || !_polling) return;
      refreshSnapshot().ignore();
      _poll();
    });
  }

  void _refreshAfterMutation() {
    _refreshAgain = true;
    refreshSnapshot().ignore();
  }

  Future<void> refreshSnapshot() =>
      _refreshing ??= _refreshLoop().whenComplete(() => _refreshing = null);

  Future<void> _refreshLoop() async {
    do {
      _refreshAgain = false;
      final epoch = _snapshotEpoch, currentGeneration = generation;
      try {
        await _refresh();
      } on Object catch (error) {
        if (!_disposed &&
            epoch == _snapshotEpoch &&
            (currentGeneration == null || currentGeneration == generation)) {
          _publishedSnapshotEpoch = null;
          _snapshotErrors.add(_safe(error).code);
        }
        rethrow;
      }
    } while (_refreshAgain && _polling && !_disposed);
  }

  Future<void> _refresh() async {
    final epoch = _snapshotEpoch;
    final profiles = await read(ApiMethod.profilesList);
    if (_disposed ||
        epoch != _snapshotEpoch ||
        generation != profiles.generation ||
        _session?.isClosed != false)
      return;
    final settings = await read(ApiMethod.settingsGet);
    if (_disposed ||
        epoch != _snapshotEpoch ||
        generation != profiles.generation ||
        profiles.generation != settings.generation ||
        profiles.result['storeRevision'] != settings.result['storeRevision'])
      return;
    final snapshot = ClientSnapshot(profiles, settings), previous = _snapshot;
    if (previous != null &&
        (BigInt.parse(snapshot.storeRevision) <
                BigInt.parse(previous.storeRevision) ||
            (_publishedSnapshotEpoch == epoch &&
                previous.generation == snapshot.generation &&
                snapshot.storeRevision == previous.storeRevision)))
      return;
    _snapshot = snapshot;
    _publishedSnapshotEpoch = epoch;
    _snapshots.add(snapshot);
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    final done = Completer<void>();
    _closing = done.future;
    done.future.ignore();
    _disposed = true;
    stopPolling();
    _heartbeatTimer?.call();
    final session = _session;
    session?.close().ignore();
    _session = null;
    _snapshot = null;
    () async {
      try {
        await _connecting;
      } catch (_) {
        /* opening owns cleanup */
      }
      await _retiring;
      await _detach();
      _states.add(ClientConnectionState.closed);
      _states.close().ignore();
      _snapshots.close().ignore();
      _snapshotErrors.close().ignore();
    }().then<void>(
      done.complete,
      onError: (Object error, StackTrace _) => done.completeError(_safe(error)),
    );
    return done.future;
  }
}

EngineApiException _safe(Object error) => switch (error) {
  EngineApiException() => error,
  EngineCallFailure() => EngineApiException(
    ErrorCode.values.where((c) => c.wireName == error.code).firstOrNull ??
        ErrorCode.serviceUnavailable,
    field: error.field,
  ),
  TimeoutException() => const EngineApiException(ErrorCode.timeout),
  FormatException() => const EngineApiException(ErrorCode.validation),
  _ => const EngineApiException(ErrorCode.serviceUnavailable),
};
