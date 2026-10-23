import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_protocol/wire.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';

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

/// Transport owns its native buffers until each operation/close has completed.
abstract interface class ClientTransport {
  Future<void> verifyPeer();
  Future<Uint8List> read(int count, Duration deadline);
  Future<void> write(List<int> bytes, Duration deadline);
  Future<void> close();
}

/// T031 supplies an endpoint from a verified bundle and DPAPI discovery.
class ClientEndpoint {
  ClientEndpoint({
    required this.transport,
    required this.generation,
    required this.buildId,
    required List<int> bootstrapToken,
  }) : _token = Uint8List.fromList(bootstrapToken) {
    try {
      requireUuid(generation);
      if (bootstrapToken.length != 32 ||
          bootstrapToken.any((b) => b < 0 || b > 255)) {
        throw const LocalApiException(ErrorCode.unauthorized);
      }
    } catch (_) {
      _token.fillRange(0, _token.length, 0);
      throw const LocalApiException(ErrorCode.unauthorized);
    }
  }
  final ClientTransport transport;
  final String generation, buildId;
  final Uint8List _token;
  void clearToken() => _token.fillRange(0, _token.length, 0);
}

class LocalApiException implements Exception {
  const LocalApiException(this.code, {this.field});
  final ErrorCode code;
  final String? field;
  RetryAdvice get retry => LocalError(code).retry;
  @override
  String toString() => 'LocalApiException: ${code.wireName}';
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
        throw const LocalApiException(ErrorCode.validation);
      return MutationIntent._(
        method,
        id,
        Uint8List.fromList(
          StrictCodec().encode(params, maxBytes: maxRequestBytes),
        ),
      );
    } catch (_) {
      throw const LocalApiException(ErrorCode.validation);
    }
  }
  MutationIntent._(this.method, this.id, this._params);
  final ApiMethod method;
  final String id;
  final Uint8List _params;
  bool _disposed = false;
  Map<String, Object?> _copyParams() {
    if (_disposed) throw const LocalApiException(ErrorCode.validation);
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

class LocalApiClient {
  LocalApiClient({
    required Future<ClientEndpoint> Function() connect,
    Duration Function()? elapsed,
    ScheduleDeadline schedule = _defaultSchedule,
    Set<Capability>? capabilities,
  }) : _connector = connect,
       _trustedConnector = null,
       _schedule = schedule,
       _capabilities = Set.unmodifiable(
         capabilities ?? Capability.values.toSet(),
       ) {
    _elapsed = elapsed ?? () => _watch.elapsed;
  }
  LocalApiClient.trusted({
    required Future<(TrustedApiClient, String)> Function() connect,
    ScheduleDeadline schedule = _defaultSchedule,
  }) : _connector = null,
       _trustedConnector = connect,
       _schedule = schedule,
       _capabilities = const {} {
    _elapsed = () => _watch.elapsed;
  }
  final Future<ClientEndpoint> Function()? _connector;
  final Future<(TrustedApiClient, String)> Function()? _trustedConnector;
  TrustedApiClient? _trustedClient;
  String? _trustedGeneration;
  Future<TrustedApiClient>? _trustedConnecting;
  TrustedApiClient? get trustedClient => _trustedClient;

  /// Revalidate presentation data with the codec belonging to this client.
  /// No native identity or authorization is synthesized by this projection.
  void captureResult(String method, Map<String, Object?> value) {
    if (_trustedConnector != null) {
      captureTrustedMethodResult(method, value);
    } else {
      validateMethodResult(method, value);
    }
  }

  final ScheduleDeadline _schedule;
  final Set<Capability> _capabilities;
  final _watch = Stopwatch()..start();
  late final Duration Function() _elapsed;
  final _states = StreamController<ClientConnectionState>.broadcast();
  final _snapshots = StreamController<ClientSnapshot>.broadcast();
  // Synchronous safe-code delivery prevents an error from a retired poll epoch
  // arriving after the UI has already entered a fresh ready epoch.
  final _snapshotErrors = StreamController<ErrorCode>.broadcast(sync: true);
  _ClientSession? _session;
  Future<_ClientSession>? _connecting;
  Future<void> _retiring = Future.value();
  Future<void>? _refreshing, _closing;
  CancelDeadline? _heartbeatTimer, _pollTimer;
  bool _disposed = false, _polling = false;
  bool _refreshAgain = false;
  int _snapshotEpoch = 0;
  int? _publishedSnapshotEpoch;
  ClientSnapshot? _snapshot;
  Stream<ClientConnectionState> get states => _states.stream;
  Stream<ClientSnapshot> get snapshots => _snapshots.stream;
  Stream<ErrorCode> get snapshotErrors => _snapshotErrors.stream;
  String? get generation =>
      _trustedConnector != null ? _trustedGeneration : _session?.generation;

  Future<void> connect() async {
    if (_trustedConnector != null) {
      await _connectedTrusted();
    } else {
      await _connected();
    }
  }

  Future<TrustedApiClient> _connectedTrusted() {
    if (_disposed)
      return Future.error(
        const LocalApiException(ErrorCode.serviceUnavailable),
      );
    final current = _trustedClient;
    if (current != null && !current.isClosed) return Future.value(current);
    return _trustedConnecting ??= _openTrusted().whenComplete(
      () => _trustedConnecting = null,
    );
  }

  Future<TrustedApiClient> _openTrusted() async {
    _states.add(ClientConnectionState.connecting);
    TrustedApiClient? client;
    try {
      await _retiring;
      if (_disposed)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      final connection = await _trustedConnector!();
      client = connection.$1;
      requireUuid(connection.$2);
      if (_disposed || client.isClosed)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      _trustedClient = client;
      _trustedGeneration = connection.$2;
      final owned = client;
      owned.done
          .then(
            (_) => _trustedFailed(owned),
            onError: (Object error) => _trustedFailed(owned),
          )
          .ignore();
      _states.add(ClientConnectionState.connected);
      _heartbeatTrusted(owned);
      return owned;
    } on Object catch (error) {
      if (client != null) {
        _retiring = client.close();
        try {
          await _retiring;
        } on Object catch (cleanup) {
          throw _safe(cleanup);
        }
      }
      if (!_disposed) _states.add(ClientConnectionState.disconnected);
      throw _safe(error);
    }
  }

  void _trustedFailed(TrustedApiClient client) {
    if (!identical(client, _trustedClient)) return;
    _trustedClient = null;
    _trustedGeneration = null;
    _heartbeatTimer?.call();
    _retiring = client.close();
    _retiring.ignore();
    if (!_disposed) _states.add(ClientConnectionState.disconnected);
  }

  void _heartbeatTrusted(TrustedApiClient client) {
    _heartbeatTimer?.call();
    if (_disposed || !identical(client, _trustedClient) || client.isClosed)
      return;
    _heartbeatTimer = _schedule(heartbeatInterval, () async {
      try {
        await client.call('session.ping', {});
      } on Object catch (error) {
        if (_safe(error).code != ErrorCode.resourceLimit) {
          await client.close();
          _trustedFailed(client);
        }
      } finally {
        _heartbeatTrusted(client);
      }
    });
  }

  Future<ApiReply> _trustedCall(
    ApiMethod method,
    Map<String, Object?> params,
    String id,
  ) async {
    try {
      final client = await _connectedTrusted();
      final currentGeneration = _trustedGeneration!;
      final result = await client.call(method.wireName, params, requestId: id);
      if (_disposed ||
          !identical(client, _trustedClient) ||
          currentGeneration != _trustedGeneration)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      return ApiReply(currentGeneration, result);
    } on Object catch (error) {
      throw _safe(error);
    }
  }

  Future<_ClientSession> _connected() {
    if (_disposed)
      return Future.error(
        const LocalApiException(ErrorCode.serviceUnavailable),
      );
    final existing = _session;
    if (existing != null && !existing.closed) return Future.value(existing);
    return _connecting ??= _open().whenComplete(() => _connecting = null);
  }

  Future<_ClientSession> _open() async {
    _states.add(ClientConnectionState.connecting);
    ClientEndpoint? endpoint;
    try {
      await _retiring;
      if (_disposed)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      endpoint = await _connector!();
      if (_disposed)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      final session = await _authenticate(endpoint);
      if (_disposed)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      _session = session;
      session.listen();
      _states.add(ClientConnectionState.connected);
      _heartbeat(session);
      return session;
    } catch (error) {
      Object failure = error;
      if (endpoint != null) {
        endpoint.clearToken();
        _retiring = Future<void>.sync(endpoint.transport.close);
        try {
          await _retiring;
        } on Object catch (cleanupError) {
          failure = cleanupError;
        }
      }
      if (!_disposed) _states.add(ClientConnectionState.disconnected);
      throw _safe(failure);
    }
  }

  Future<_ClientSession> _authenticate(ClientEndpoint endpoint) async {
    final deadline = _elapsed() + rpcDeadline;
    Duration remaining() {
      final time = deadline - _elapsed();
      if (time <= Duration.zero)
        throw const LocalApiException(ErrorCode.timeout);
      return time;
    }

    final secret = SecretKeyData(
      List.of(endpoint._token),
      overwriteWhenDestroyed: true,
    );
    try {
      await endpoint.transport.verifyPeer().timeout(remaining());
      final codec = StrictCodec();
      final hello = codec.decode(
        await _frame(
          endpoint.transport,
          remaining,
          _elapsed,
          maxHandshakeBytes,
        ),
      );
      validateHello(hello);
      if ((hello['hello'] as Map)['generation'] != endpoint.generation) {
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      }
      final nonce = base64Url
          .encode(List.generate(32, (_) => Random.secure().nextInt(256)))
          .replaceAll('=', '');
      final caps = _capabilities.map((c) => c.wireName).toList()..sort();
      final serverNonce = (hello['hello'] as Map)['serverNonce'];
      Future<List<int>> mac(
        String role, [
        String? session,
        List<String>? grants,
      ]) async {
        final bytes = Uint8List.fromList(
          utf8.encode(
            '$role\n1\ndefault\n${endpoint.generation}\n$serverNonce\n$nonce\n${endpoint.buildId}\n${caps.join(',')}${session == null ? '' : '\n$session\n${grants!.join(',')}'}',
          ),
        );
        try {
          return (await Hmac.sha256().calculateMac(
            bytes,
            secretKey: secret,
          )).bytes;
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }

      final proof = await mac('client');
      final auth = Uint8List.fromList(
        frameBytes(
          codec.encode({
            'authenticate': {
              'clientNonce': nonce,
              'clientBuildId': endpoint.buildId,
              'requestedCapabilities': caps,
              'proof': base64Url.encode(proof).replaceAll('=', ''),
            },
          }, maxBytes: maxHandshakeBytes),
          maxBytes: maxHandshakeBytes,
        ),
      );
      final writing = endpoint.transport.write(auth, remaining());
      try {
        await writing.timeout(remaining());
      } catch (_) {
        try {
          await endpoint.transport.close();
        } finally {
          try {
            await writing;
          } on Object {
            /* Actual write completed, including cancellation failure. */
          }
        }
        rethrow;
      } finally {
        auth.fillRange(0, auth.length, 0);
      }
      final grant = codec.decode(
        await _frame(
          endpoint.transport,
          remaining,
          _elapsed,
          maxHandshakeBytes,
        ),
      );
      validateAuthenticated(grant);
      final body = grant['authenticated'] as Map<String, Object?>;
      final granted = (body['capabilities'] as List).cast<String>();
      if (granted.any((c) => !caps.contains(c)))
        throw const LocalApiException(ErrorCode.unauthorized);
      final session = body['sessionId'] as String;
      final expected = await mac('server', session, granted);
      final actual = base64Url.decode('${body['proof']}=');
      var mismatch = expected.length ^ actual.length;
      for (var i = 0; i < expected.length; i++) {
        mismatch |= expected[i] ^ (i < actual.length ? actual[i] : 0);
      }
      if (mismatch != 0) throw const LocalApiException(ErrorCode.unauthorized);
      await endpoint.transport.verifyPeer().timeout(remaining());
      remaining();
      return _ClientSession(
        this,
        endpoint.transport,
        endpoint.generation,
        session,
      );
    } finally {
      secret.destroy();
      endpoint.clearToken();
    }
  }

  Future<ApiReply> read(
    ApiMethod method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (method.isMutation) throw const LocalApiException(ErrorCode.validation);
    final frozen = StrictCodec().decode(
      StrictCodec().encode(params, maxBytes: maxRequestBytes),
    );
    if (_trustedConnector != null)
      return _trustedCall(method, frozen, newRequestId());
    final session = await _connected();
    return session.request(method, frozen, newRequestId());
  }

  Future<ApiReply> mutate(MutationIntent intent) async {
    final params = intent._copyParams();
    if (_trustedConnector != null) {
      try {
        final result = await _trustedCall(intent.method, params, intent.id);
        if (_polling) _refreshAfterMutation();
        return result;
      } on LocalApiException catch (error) {
        if (_polling && error.code == ErrorCode.revisionConflict)
          _refreshAfterMutation();
        rethrow;
      }
    }
    final session = await _connected();
    try {
      final reply = await session.request(intent.method, params, intent.id);
      if (_polling) _refreshAfterMutation();
      return reply;
    } on LocalApiException catch (error) {
      if (_polling && error.code == ErrorCode.revisionConflict)
        _refreshAfterMutation();
      rethrow;
    }
  }

  Future<ApiReply> mutationStatus(MutationIntent intent) =>
      read(ApiMethod.mutationsGet, {'requestId': intent.id});

  void _failed(_ClientSession session) {
    if (!identical(_session, session)) return;
    _session = null;
    _heartbeatTimer?.call();
    _retiring = session.close();
    _retiring.ignore();
    if (!_disposed) _states.add(ClientConnectionState.disconnected);
  }

  void _heartbeat(_ClientSession session) {
    _heartbeatTimer?.call();
    if (_disposed || !identical(_session, session)) return;
    _heartbeatTimer = _schedule(heartbeatInterval, () {
      _ping(session).ignore();
    });
  }

  Future<void> _ping(_ClientSession session) async {
    try {
      await session.request(ApiMethod.sessionPing, const {}, newRequestId());
    } on LocalApiException catch (error) {
      if (error.code != ErrorCode.resourceLimit) await session.close();
    } finally {
      _heartbeat(session);
    }
  }

  void startPolling() {
    if (_disposed) throw const LocalApiException(ErrorCode.serviceUnavailable);
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

  Future<void> close() =>
      _closing ??= _close().catchError((Object error) => throw _safe(error));
  Future<void> _close() async {
    _disposed = true;
    stopPolling();
    _heartbeatTimer?.call();
    try {
      await _trustedConnecting;
    } on Object {
      /* Opening owns cleanup. */
    }
    final trusted = _trustedClient;
    if (trusted != null) {
      try {
        await trusted.call('session.close', {});
      } on Object {
        /* Physical close below still retires the session. */
      }
      await trusted.close();
      _trustedClient = null;
      _trustedGeneration = null;
    }
    final session = _session;
    if (session != null && !session.closed) {
      try {
        await session.request(ApiMethod.sessionClose, const {}, newRequestId());
      } on LocalApiException {
        /* Physical close still revokes this connection. */
      }
      await session.close();
    }
    try {
      await _connecting;
    } on Object {
      /* _open closes its endpoint. */
    }
    await _retiring;
    _states.add(ClientConnectionState.closed);
    // Consumer-owned paused subscriptions must not prolong native shutdown.
    _states.close().ignore();
    _snapshots.close().ignore();
    _snapshotErrors.close().ignore();
    _snapshot = null;
    _watch.stop();
  }
}

LocalApiException _safe(Object error) => switch (error) {
  LocalApiException() => error,
  TrustedRpcException() => LocalApiException(
    ErrorCode.values.where((code) => code.wireName == error.code).firstOrNull ??
        ErrorCode.serviceUnavailable,
    field: error.field,
  ),
  StateError() => LocalApiException(
    ErrorCode.values
            .where((code) => code.wireName == error.message)
            .firstOrNull ??
        ErrorCode.serviceUnavailable,
  ),
  TimeoutException() => const LocalApiException(ErrorCode.timeout),
  FormatException() => const LocalApiException(ErrorCode.incompatible),
  _ => const LocalApiException(ErrorCode.serviceUnavailable),
};

Future<Uint8List> _frame(
  ClientTransport transport,
  Duration Function() remaining,
  Duration Function() elapsed,
  int limit,
) async {
  final header = Uint8List(4);
  Duration? partialDeadline;
  Future<void> fill(Uint8List target) async {
    var offset = 0;
    while (offset < target.length) {
      var time = remaining();
      if (partialDeadline != null && partialDeadline! - elapsed() < time)
        time = partialDeadline! - elapsed();
      if (time <= Duration.zero)
        throw const LocalApiException(ErrorCode.timeout);
      final bytes = await transport
          .read((target.length - offset).clamp(1, 65536), time)
          .timeout(time);
      if (bytes.isEmpty || bytes.length > target.length - offset)
        throw const LocalApiException(ErrorCode.serviceUnavailable);
      partialDeadline ??= elapsed() + rpcDeadline;
      target.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
      if (remaining() <= Duration.zero || elapsed() >= partialDeadline!)
        throw const LocalApiException(ErrorCode.timeout);
    }
  }

  await fill(header);
  final count = ByteData.sublistView(header).getUint32(0, Endian.little);
  if (count == 0 || count > limit)
    throw const LocalApiException(ErrorCode.incompatible);
  final payload = Uint8List(count);
  await fill(payload);
  return payload;
}

class _Pending {
  _Pending(this.method, this.bytes, this.signature);
  final ApiMethod method;
  final Uint8List bytes;
  final Uint8List signature;
  final result = Completer<ApiReply>();
  CancelDeadline? cancel;
  bool writing = false;
  void clear() {
    cancel?.call();
    signature.fillRange(0, signature.length, 0);
    if (!writing) bytes.fillRange(0, bytes.length, 0);
  }
}

class _ClientSession {
  _ClientSession(this.client, this.transport, this.generation, this.sessionId);
  final LocalApiClient client;
  final ClientTransport transport;
  final String generation, sessionId;
  final _pending = <String, _Pending>{};
  Future<void> _writes = Future.value();
  Future<void>? _closing;
  bool closed = false;
  Future<ApiReply> request(
    ApiMethod method,
    Map<String, Object?> params,
    String id,
  ) {
    if (closed)
      return Future.error(
        const LocalApiException(ErrorCode.serviceUnavailable),
      );
    final signature = Uint8List.fromList(
      StrictCodec().encode(params, maxBytes: maxRequestBytes),
    );
    final existing = _pending[id];
    if (existing != null) {
      var same =
          method == existing.method &&
          signature.length == existing.signature.length;
      for (var i = 0; same && i < signature.length; i++) {
        same = signature[i] == existing.signature[i];
      }
      signature.fillRange(0, signature.length, 0);
      return same
          ? existing.result.future
          : Future.error(
              const LocalApiException(ErrorCode.idempotencyConflict),
            );
    }
    if (_pending.length >= maxPendingPerSession) {
      signature.fillRange(0, signature.length, 0);
      return Future.error(const LocalApiException(ErrorCode.resourceLimit));
    }
    final bytes = Uint8List.fromList(
      frameBytes(
        StrictCodec().encode({
          'v': 1,
          'id': id,
          'sessionId': sessionId,
          'method': method.wireName,
          'params': params,
        }, maxBytes: maxRequestBytes),
        maxBytes: maxRequestBytes,
      ),
    );
    final pending = _Pending(method, bytes, signature);
    _pending[id] = pending;
    pending.cancel = client._schedule(rpcDeadline, () {
      if (_pending.remove(id) != pending) return;
      pending.clear();
      pending.result.completeError(const LocalApiException(ErrorCode.timeout));
    });
    final until = client._elapsed() + rpcDeadline;
    _writes = _writes.then((_) async {
      if (closed || _pending[id] != pending) {
        pending.clear();
        return;
      }
      pending.writing = true;
      Future<void>? writing;
      try {
        final remaining = until - client._elapsed();
        if (remaining <= Duration.zero)
          throw const LocalApiException(ErrorCode.timeout);
        writing = transport.write(bytes, remaining);
        await writing.timeout(remaining);
      } catch (_) {
        try {
          await close();
        } finally {
          if (writing != null) {
            try {
              await writing;
            } on Object {
              /* Actual write completed, even if close failed. */
            }
          }
        }
      } finally {
        pending.writing = false;
        bytes.fillRange(0, bytes.length, 0);
      }
    });
    _writes.ignore();
    return pending.result.future;
  }

  void listen() => _listen().ignore();
  Future<void> _listen() async {
    try {
      while (!closed) {
        final idle = client._elapsed() + sessionLease;
        final bytes = await _frame(
          transport,
          () => idle - client._elapsed(),
          client._elapsed,
          maxResponseBytes,
        );
        final response = StrictCodec().decode(
          bytes,
          maxBytes: maxResponseBytes,
        );
        validateResponseEnvelope(response);
        if (response['generation'] != generation) continue;
        final id = response['id'] as String, pending = _pending[id];
        if (pending == null) continue;
        final error = response['error'] as Map<String, Object?>?;
        if (error == null) {
          final result = response['result'] as Map<String, Object?>;
          validateMethodResult(pending.method.wireName, result);
          if (pending.method == ApiMethod.readinessGet &&
              result['generation'] != generation)
            throw const LocalApiException(ErrorCode.incompatible);
          _pending.remove(id);
          pending.clear();
          pending.result.complete(ApiReply(generation, result));
        } else {
          _pending.remove(id);
          pending.clear();
          pending.result.completeError(
            LocalApiException(
              ErrorCode.values.singleWhere((c) => c.wireName == error['code']),
              field: error['field'] as String?,
            ),
          );
        }
      }
    } catch (_) {
      await close();
    }
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    closed = true;
    final done = Completer<void>();
    _closing = done.future;
    _close().then(done.complete, onError: done.completeError);
    return _closing!;
  }

  Future<void> _close() async {
    closed = true;
    for (final pending in _pending.values) {
      pending.clear();
      pending.result.completeError(
        const LocalApiException(ErrorCode.serviceUnavailable),
      );
    }
    _pending.clear();
    client._failed(this);
    await transport.close();
  }
}
