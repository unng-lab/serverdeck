import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/discovery.dart';
import 'package:serverdeck_protocol/errors.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../credentials/mcp_credential_files.dart';
import '../platform/ports.dart';

part 'client_bootstrap.dart';
part 'client_grant.dart';
part 'client_rpc.dart';

enum McpClientFailureOrigin { local, remote, transport }

final class McpClientException implements Exception {
  const McpClientException(this.code, this.origin);
  final String code;
  final McpClientFailureOrigin origin;
  bool get terminal => origin == McpClientFailureOrigin.transport;
  RetryAdvice get retry => TrustedLocalError(code).retry;
  @override
  String toString() => 'McpClientException($code,${origin.name})';
}

String _nonce() => base64Url
    .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
    .replaceAll('=', '');
String _id() {
  final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String _safe(Object error) => error is TimeoutException
    ? 'TIMEOUT'
    : error is McpClientException
    ? error.code
    : error is StateError &&
          const {
            'TIMEOUT',
            'UNAUTHORIZED',
            'FORBIDDEN',
            'INCOMPATIBLE',
            'NOT_READY',
            'RESOURCE_LIMIT',
            'STORAGE_BLOCKED',
            'SERVICE_UNAVAILABLE',
          }.contains(error.message)
    ? error.message
    : 'SERVICE_UNAVAILABLE';

/// One MCP-only connection attempt. Construct/retain this owner BEFORE awaiting
/// authenticate. Native channel proof is an OS port, not a request DTO or role.
/// The root verifies descriptor PID when connecting the actual native channel.
/// This client never opens a store, writer lease, app or another connection.
final class McpClient {
  McpClient({
    required VerifiedMcpChannel peer,
    required DiscoveryDescriptor descriptor,
    EngineClock? clock,
    Duration bootstrapBudget = rpcDeadline,
  }) : _peer = peer,
       _clock = clock ?? SystemEngineClock(),
       generation = descriptor.generation,
       workspaceId = descriptor.workspaceId,
       _owner = peer.ownerIdentity,
       _root = peer.appRoot,
       _build = peer.buildId {
    if (bootstrapBudget <= Duration.zero ||
        bootstrapBudget > rpcDeadline ||
        descriptor.ownerSid != _owner ||
        descriptor.buildId != _build) {
      throw ArgumentError('INVALID_MCP_CONNECTION');
    }
    _bootstrapUntil = _clock.elapsed + bootstrapBudget;
    _token = Uint8List.fromList(descriptor.bootstrapToken);
    _done.future.ignore();
  }
  final VerifiedMcpChannel _peer;
  final EngineClock _clock;
  final String generation, workspaceId, _owner, _root, _build;
  late final Duration _bootstrapUntil;
  late final Uint8List _token;
  final _work = <Future<void>>{};
  final _pending = <String, _Pending>{};
  final _done = Completer<void>();
  final _retired = Completer<void>();
  Future<void>? _authentication, _closing, _grantOpening;
  Future<void> _writeTail = Future.value();
  OperationalHello? _hello;
  String? _session;
  McpOpenResult? _grant;
  bool _closed = false, _authenticated = false, _grantBusy = false;
  bool get isClosed => _closed;
  int get pendingRequests => _pending.length;
  Future<void> get done => _done.future;

  /// Logical loss, before physical drain. This is never a close confirmation.
  Future<void> get retired => _retired.future;
  McpOpenResult? get grant => _closed ? null : _grant;

  void _check() {
    if (_closed) throw StateError('SERVICE_UNAVAILABLE');
    if (_peer.ownerIdentity != _owner ||
        _peer.appRoot != _root ||
        _peer.buildId != _build) {
      throw StateError('UNAUTHORIZED');
    }
  }

  Duration _remaining(Duration until) {
    _check();
    final left = until - _clock.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  // Registration precedes all provider callouts. Settlement, including a late
  // failure, remains owned independently of any caller-facing timeout/result.
  Future<T> _owned<T>(Future<T> Function() operation) {
    final settled = Completer<void>();
    _work.add(settled.future);
    final actual = Future<T>.sync(operation);
    actual.then<void>(
      (_) {
        _work.remove(settled.future);
        settled.complete();
      },
      onError: (Object _, StackTrace __) {
        _work.remove(settled.future);
        settled.complete();
      },
    );
    return actual;
  }

  void _observe(Future<void> actual) {
    _owned(() => actual).ignore();
  }

  Future<void> _proof(Duration until) async {
    _remaining(until);
    await _owned(() => _peer.revalidate(observeNativeCompletion: _observe))
        .timeout(_remaining(until));
    _remaining(until);
  }

  Future<Uint8List> _fill(int count, Duration Function() remaining) async {
    final result = Uint8List(count);
    var offset = 0;
    try {
      while (offset < count) {
        final bytes = await _owned(
          () => _peer.read(
            count: (count - offset).clamp(1, 65536),
            deadline: remaining(),
          ),
        );
        try {
          remaining();
          if (bytes.isEmpty || bytes.length > count - offset)
            throw StateError('SERVICE_UNAVAILABLE');
          result.setRange(offset, offset + bytes.length, bytes);
          offset += bytes.length;
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      return result;
    } catch (_) {
      result.fillRange(0, result.length, 0);
      rethrow;
    }
  }

  Future<Uint8List> _handshakeFrame(Duration until) async {
    final header = await _fill(4, () => _remaining(until));
    final size = ByteData.sublistView(header).getUint32(0, Endian.little);
    header.fillRange(0, header.length, 0);
    if (size < 1 || size > maxHandshakeBytes) throw StateError('UNAUTHORIZED');
    return _fill(size, () => _remaining(until));
  }

  Future<void> _handshakeWrite(
    Map<String, Object?> message,
    Duration until,
  ) async {
    final bytes = Uint8List.fromList(
      frameBytes(
        StrictCodec().encode(message, maxBytes: maxHandshakeBytes),
        maxBytes: maxHandshakeBytes,
      ),
    );
    try {
      await _owned(() => _peer.write(bytes, deadline: _remaining(until)));
      _remaining(until);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<TrustedReadiness> readiness() async {
    final value = TrustedReadiness.fromJson(await call('readiness.get', {}));
    if (value.generation != generation ||
        value.state == ReadinessState.ready &&
            value.workspaceId != workspaceId) {
      close().ignore();
      throw const McpClientException(
        'INCOMPATIBLE',
        McpClientFailureOrigin.transport,
      );
    }
    return value;
  }

  Future<void> close() => _terminate('SERVICE_UNAVAILABLE');

  /// Liveness only for fixed, data-free stdio responses. Domain publication
  /// still requires its native gate plus current-policy session.ping.
  Future<void> verifyLive({Duration deadline = rpcDeadline}) {
    if (!_authenticated ||
        _closed ||
        deadline <= Duration.zero ||
        deadline > rpcDeadline) {
      return Future.error(StateError('SERVICE_UNAVAILABLE'));
    }
    return _owned(() async {
      try {
        await _proof(_clock.elapsed + deadline);
      } catch (e) {
        _terminate(_safe(e)).ignore();
        throw StateError(_safe(e));
      }
    });
  }

  Future<void> _terminate(String code) {
    if (_closing != null) return _closing!;
    _closing = _done.future;
    _closed = true;
    _retired.complete();
    _token.fillRange(0, _token.length, 0);
    for (final pending in _pending.values.toList()) {
      pending.timer?.cancel();
      if (!pending.result.isCompleted)
        pending.result.completeError(
          McpClientException(code, McpClientFailureOrigin.transport),
        );
    }
    _pending.clear();
    () async {
      var clean = true;
      try {
        await Future<void>.sync(_peer.disconnect);
      } catch (_) {
        clean = false;
      }
      while (_work.isNotEmpty) {
        await Future.wait(_work.toList());
      }
      if (!clean)
        throw const McpClientException(
          'SERVICE_UNAVAILABLE',
          McpClientFailureOrigin.transport,
        );
    }().then<void>(
      _done.complete,
      onError: (Object _, StackTrace __) => _done.completeError(
        const McpClientException(
          'SERVICE_UNAVAILABLE',
          McpClientFailureOrigin.transport,
        ),
      ),
    );
    return _done.future;
  }
}
