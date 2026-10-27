import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';

import 'lifecycle.dart';

/// The adapter must check live authorization and schemas before lookup/start and
/// again before returning data. Cancellation drops read/response interest only;
/// admitted durable mutations survive this session and remain queryable.
abstract interface class McpGateway {
  McpInvocation start(String method, Map<String, Object?> params);
  Future<void> close();
}

final class McpGatewayFailure implements Exception {
  const McpGatewayFailure(this.code);
  final ErrorCode code;
  @override
  String toString() => 'McpGatewayFailure(${code.wireName})';
}

final class McpInvocation {
  const McpInvocation(
    this.result,
    this.cancelInterest, {
    this.beforePublish,
    this.validatePublication,
    this.afterPublish,
  });
  final Future<Map<String, Object?>> result;
  final Future<void> Function() cancelInterest;
  final Future<void> Function()? beforePublish, afterPublish;
  final void Function()? validatePublication;
}

final class _Pending {
  _Pending(this.invocation);
  final McpInvocation invocation;
  final cancelled = Completer<Map<String, Object?>?>();
  bool interest = true;
}

/// Bounded stdio engine. No stdout logging, credentials, storage or SSH access.
/// The executable supplies stdin, flushed stdout writes and a verified gateway.
final class McpServer {
  McpServer({
    required Stream<List<int>> input,
    required Future<void> Function(List<int>) write,
    required McpGateway gateway,
    void Function(String)? diagnostic,
  }) : this._(
         input,
         write,
         gateway,
         diagnostic,
         const Duration(seconds: 30),
         const Duration(seconds: 5),
         const Duration(seconds: 35),
       );

  /// Internal test seam only; no runtime configuration/CLI timeout overrides.
  McpServer.forTesting({
    required Stream<List<int>> input,
    required Future<void> Function(List<int>) write,
    required McpGateway gateway,
    void Function(String)? diagnostic,
    required Duration initializationTimeout,
    required Duration writeTimeout,
    required Duration callTimeout,
  }) : this._(
         input,
         write,
         gateway,
         diagnostic,
         initializationTimeout,
         writeTimeout,
         callTimeout,
       );

  McpServer._(
    this._input,
    this._write,
    this._gateway,
    this._diagnostic,
    this._initializationTimeout,
    this._writeTimeout,
    this._callTimeout,
  );
  final Stream<List<int>> _input;
  final Future<void> Function(List<int>) _write;
  final McpGateway _gateway;
  final void Function(String)? _diagnostic;
  final Duration _initializationTimeout, _writeTimeout, _callTimeout;
  final _lifecycle = McpLifecycle();
  final _line = Uint8List(mcpMaxRequestBytes);
  final _pending = <Object, _Pending>{};
  final _done = Completer<int>();
  Future<void> _writeTail = Future.value();
  int _length = 0, _queuedWrites = 0;
  bool _started = false;
  bool get _closed => _done.isCompleted;
  int get pendingRequests => _pending.length;
  int get bufferedBytes => _length;

  Future<int> run() async {
    if (_started) throw StateError('ALREADY_STARTED');
    _started = true;
    final iterator = StreamIterator(_input);
    final initialization = Timer(_initializationTimeout, () {
      _lifecycle.expireInitialization();
      if (_lifecycle.phase == McpPhase.closed && !_closed) {
        _report('INITIALIZATION_TIMEOUT');
        _stop(2);
      }
    });
    unawaited(_read(iterator));
    final code = await _done.future;
    initialization.cancel();
    // Detach transport/read interests promptly, including never-completing
    // adapters. Closing a gateway must never cancel an admitted durable job.
    final cancellation = <Future<void>>[
      iterator.cancel(),
      for (final pending in _pending.values) _cancel(pending),
    ];
    _pending.clear();
    cancellation.add(_safeClose());
    try {
      await Future.wait(cancellation).timeout(_writeTimeout);
    } catch (_) {
      _report('CLOSE_FAILED');
    }
    return code;
  }

  Future<void> _safeClose() async {
    try {
      await _gateway.close();
    } catch (_) {
      _report('CLOSE_FAILED');
    }
  }

  Future<void> _read(StreamIterator<List<int>> iterator) async {
    try {
      while (!_closed && await iterator.moveNext()) {
        // StreamIterator pauses the input between chunks, including while a
        // response write blocks. Only this bounded line is accumulated here.
        for (final byte in iterator.current) {
          if (_closed) break;
          if (byte == 10) {
            final frame = Uint8List.fromList(_line.sublist(0, _length));
            _length = 0;
            await _frame(frame);
          } else {
            if (_length == _line.length) {
              await _fatalParse();
              break;
            }
            _line[_length++] = byte;
          }
        }
      }
      if (!_closed) {
        if (_length != 0) {
          await _fatalParse();
        } else {
          _stop(0);
        }
      }
    } catch (_) {
      if (!_closed) {
        _report('READ_FAILED');
        _stop(2);
      }
    }
  }

  Future<void> _fatalParse() async {
    await _send(const McpProtocolException(-32700).response(null));
    _stop(2);
  }

  Future<void> _frame(List<int> bytes) async {
    try {
      utf8.decode(bytes, allowMalformed: false);
    } on FormatException {
      await _fatalParse();
      return;
    }
    late final McpInbound request;
    try {
      request = McpInbound.decode(bytes);
    } on McpProtocolException catch (error) {
      await _send(error.response(null));
      return;
    }
    final id = request.id;
    if (!request.isNotification && _pending.containsKey(id)) {
      await _send(const McpProtocolException(-32600).response(id));
      return;
    }
    if (!request.isNotification && _pending.length >= 16) {
      await _send(_failure(request, 'RESOURCE_LIMIT'));
      return;
    }
    try {
      final dispatch = _lifecycle.accept(request);
      switch (dispatch) {
        case McpIgnored():
          return;
        case McpCancelInterest():
          final pending = _pending.remove(dispatch.requestId);
          if (pending != null) await _cancel(pending);
        case McpBuiltin():
          await _send(mcpSuccess(id!, dispatch.result));
        case McpForward():
          final invocation = _gateway.start(request.method, request.params);
          final pending = _Pending(invocation);
          _pending[id!] = pending;
          unawaited(_complete(request, pending));
      }
    } on McpGatewayFailure catch (error) {
      if (!request.isNotification)
        await _send(_failure(request, error.code.wireName));
    } on McpProtocolException catch (error) {
      if (!request.isNotification) await _send(error.response(id));
    } catch (_) {
      if (!request.isNotification)
        await _send(const McpProtocolException(-32603).response(id));
    }
  }

  bool _current(Object id, _Pending pending) =>
      !_closed && pending.interest && identical(_pending[id], pending);

  Future<void> _complete(McpInbound request, _Pending pending) async {
    final id = request.id!;
    Map<String, Object?>? response;
    var gatewayData = false;
    try {
      final result = await Future.any<Map<String, Object?>?>([
        pending.invocation.result,
        pending.cancelled.future,
      ]).timeout(_callTimeout);
      if (result == null) return;
      response = mcpSuccess(id, result);
      gatewayData = true;
    } on McpGatewayFailure catch (error) {
      response = _failure(request, error.code.wireName);
    } on TimeoutException {
      unawaited(_cancel(pending, discard: false));
      response = _failure(request, 'TIMEOUT');
    } on McpProtocolException catch (error) {
      response = error.response(id);
    } catch (_) {
      response = const McpProtocolException(-32603).response(id);
    }
    try {
      if (_current(id, pending))
        await _send(
          response,
          current: () => _current(id, pending),
          publication: gatewayData ? pending.invocation : null,
          publicationFailure: (code) => _failure(request, code.wireName),
        );
    } finally {
      if (identical(_pending[id], pending)) _pending.remove(id);
    }
  }

  Future<void> _cancel(_Pending pending, {bool discard = true}) async {
    if (discard) {
      pending.interest = false;
      if (!pending.cancelled.isCompleted) pending.cancelled.complete(null);
    }
    try {
      await pending.invocation.cancelInterest().timeout(_writeTimeout);
    } catch (_) {
      _report('CANCEL_FAILED');
    }
  }

  Map<String, Object?> _failure(McpInbound request, String code) {
    if (request.method != 'tools/call') {
      return {
        'jsonrpc': '2.0',
        'id': request.id,
        'error': {'code': -32000, 'message': code},
      };
    }
    final failure = <String, Object?>{
      'ok': false,
      'error': {'code': code, 'boundary': 'local', 'retry': 'none'},
    };
    return mcpSuccess(request.id!, {
      'content': [
        {'type': 'text', 'text': jsonEncode(failure)},
      ],
      'structuredContent': failure,
      'isError': true,
    });
  }

  Future<void> _send(
    Map<String, Object?> message, {
    bool Function()? current,
    McpInvocation? publication,
    Map<String, Object?> Function(ErrorCode)? publicationFailure,
  }) async {
    if (_closed) return;
    if (_queuedWrites >= 32) {
      _report('WRITE_QUEUE_LIMIT');
      _stop(2);
      return;
    }
    late final List<int> bytes;
    try {
      bytes = encodeMcpMessage(message);
    } on McpProtocolException {
      bytes = encodeMcpMessage(
        const McpProtocolException(-32603).response(message['id']),
      );
    }
    _queuedWrites++;
    final write = _writeTail
        .then((_) async {
          if (_closed || (current != null && !current())) return;
          final clock = Stopwatch()..start();
          Duration remaining() {
            final left = _writeTimeout - clock.elapsed;
            if (left <= Duration.zero) throw TimeoutException('WRITE_FAILED');
            return left;
          }

          Future<void>? guard, issuedWrite;
          Future<void>? release;
          Future<void> cleanup() {
            // Publish completion before invoking a potentially reentrant release.
            if (release != null) return release!;
            final done = Completer<void>();
            release = done.future;
            Future<void>.sync(() => publication?.afterPublish?.call())
                .then(done.complete, onError: done.completeError);
            return done.future;
          }

          try {
            var output = bytes;
            try {
              if (publication != null) {
                guard = Future<void>.sync(
                  () => publication.beforePublish?.call(),
                );
                await guard.timeout(remaining());
                if (_closed || (current != null && !current())) return;
                publication.validatePublication?.call();
              }
            } on TimeoutException {
              rethrow;
            } catch (error) {
              final code = error is McpGatewayFailure
                  ? error.code
                  : ErrorCode.internal;
              output = encodeMcpMessage(publicationFailure!(code));
            }
            if (_closed || (current != null && !current())) return;
            final budget = remaining();
            // No await between the last authority/identity check and issuance.
            issuedWrite = Future<void>.sync(() => _write([...output, 10]));
            await issuedWrite.timeout(budget);
          } catch (_) {
            _report('WRITE_FAILED');
            _stop(2);
          } finally {
            if (publication != null) {
              // A timed-out guard may still acquire native ownership. Observe
              // actual guard AND issued flush settlement before releasing. A
              // logical timeout alone cannot release native publication ownership.
              final settled = Future.wait<void>([
                if (guard != null)
                  guard.then<void>((_) {}, onError: (Object _) {}),
                if (issuedWrite != null)
                  issuedWrite.then<void>((_) {}, onError: (Object _) {}),
              ]);
              final cleaned = settled.then((_) => cleanup());
              cleaned.ignore();
              try {
                await cleaned.timeout(remaining());
              } catch (_) {
                _report('WRITE_FAILED');
                _stop(2);
              }
            }
          }
        })
        .whenComplete(() {
          _queuedWrites--;
        });
    _writeTail = write;
    await write;
  }

  void _report(String code) {
    try {
      _diagnostic?.call(code);
    } catch (_) {
      /* Diagnostics cannot break cleanup. */
    }
  }

  void _stop(int code) {
    if (_closed) return;
    _lifecycle.close();
    _done.complete(code);
  }
}
