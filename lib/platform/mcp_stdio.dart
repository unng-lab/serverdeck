import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:serverdeck_mcp/stdio_port.dart';

typedef McpNativeInvoke = Future<Object?> Function(
  String method,
  Object? value,
);

/// Private platform carrier, used before any UI binding exists. The native
/// counterpart owns duplicated inherited handles, not a domain engine or Host.
/// Injecting the call boundary permits RAM unit tests without native dispatch.
final class ChannelMcpStdioPort implements McpStdioPort {
  ChannelMcpStdioPort({McpNativeInvoke? invoke}) : _invoke = invoke ?? _send {
    _input = StreamController<List<int>>(
      onListen: _pump,
      onPause: () => _paused = true,
      onResume: () {
        _paused = false;
        _pump();
      },
      onCancel: () => _cancelled = true,
    );
    ready = Future<Object?>.sync(() => _invoke('attach', 1))
        .then<void>((version) {
          if (version is! int || version != 1 || _closing) throw _unavailable();
        }, onError: (Object _, StackTrace _) => throw _unavailable());
    ready.ignore();
  }

  static const channel = 'serverdeck/mcp_stdio';
  static const maxReadBytes = 64 * 1024;
  static const maxWriteBytes = 8 * 1024 * 1024 + 1;
  static const _codec = StandardMethodCodec();
  final McpNativeInvoke _invoke;
  late final StreamController<List<int>> _input;
  @override
  late final Future<void> ready;
  Future<void>? _readPhysical,
      _writePhysical,
      _diagnosticPhysical,
      _closePhysical;
  bool _reading = false, _writing = false, _closing = false;
  bool _paused = false, _cancelled = false, _eof = false;
  int _diagnostics = 0;

  static StateError _unavailable() => StateError('STDIO_UNAVAILABLE');

  /// Native termination bypasses DLL/CRT teardown locks on blocked I/O. Native
  /// permits zero only after its successful physical close acknowledgement.
  static Future<Never> finishOwned(int code) async {
    await _send('finish', code >= 0 && code <= 255 ? code : 1);
    throw _unavailable(); // A successful process termination cannot reply.
  }

  static Future<Object?> _send(String method, Object? value) {
    final reply = Completer<Object?>();
    PlatformDispatcher.instance.sendPlatformMessage(
      channel,
      _codec.encodeMethodCall(MethodCall(method, value)),
      (bytes) {
        try {
          if (bytes == null) throw _unavailable();
          reply.complete(_codec.decodeEnvelope(bytes));
        } catch (_) {
          reply.completeError(_unavailable());
        }
      },
    );
    return reply.future;
  }

  @override
  Stream<List<int>> get input => _input.stream;

  void _pump() {
    if (_reading || _paused || _cancelled || _closing || _eof) return;
    _reading = true;
    final physical = _read();
    _readPhysical = physical;
    physical.ignore();
  }

  Future<void> _read() async {
    try {
      await ready;
      if (_closing || _cancelled) return;
      final result = await _invoke('read', null);
      if (_closing || _cancelled) return;
      if (result is! Uint8List || result.length > maxReadBytes) {
        throw _unavailable();
      }
      if (result.isEmpty) {
        _eof = true;
        unawaited(_input.close());
      } else {
        // Own the received bytes even when a scripted provider reuses its buffer.
        _input.add(Uint8List.fromList(result));
      }
    } catch (_) {
      if (!_closing && !_cancelled) {
        _eof = true;
        _input.addError(_unavailable(), StackTrace.empty);
        unawaited(_input.close());
      }
    } finally {
      _reading = false;
      if (!_closing && !_cancelled && !_paused && !_eof) {
        scheduleMicrotask(_pump);
      }
    }
  }

  @override
  Future<void> write(List<int> bytes) {
    if (_closing || _writing || bytes.isEmpty || bytes.length > maxWriteBytes) {
      return Future.error(_unavailable());
    }
    // Charge before awaiting attach or the actual native write.
    _writing = true;
    final snapshot = Uint8List.fromList(bytes);
    final physical = _write(snapshot);
    _writePhysical = physical;
    physical.ignore();
    return physical;
  }

  Future<void> _write(Uint8List bytes) async {
    try {
      await ready;
      if (_closing || await _invoke('write', bytes) != true) {
        throw _unavailable();
      }
    } catch (_) {
      throw _unavailable();
    } finally {
      // This runs after the native ACK/error, never on a logical timeout.
      bytes.fillRange(0, bytes.length, 0);
      _writing = false;
    }
  }

  @override
  void diagnostic(String code) {
    if (_closing || _diagnosticPhysical != null || _diagnostics >= 32) return;
    if (!RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(code)) return;
    _diagnostics++;
    final physical = _diagnostic(code);
    _diagnosticPhysical = physical;
    physical.whenComplete(() => _diagnosticPhysical = null).ignore();
  }

  Future<void> _diagnostic(String code) async {
    try {
      await ready;
      if (!_closing) await _invoke('diagnostic', 'MCP:$code\n');
    } catch (_) {
      // Diagnostics are bounded and best effort. Never echo platform exceptions.
    }
  }

  @override
  Future<void> flushDiagnostics() => _diagnosticPhysical ?? Future.value();

  @override
  Future<void> close() {
    if (_closePhysical != null) return _closePhysical!;
    _closing = true;
    _cancelled = true;
    final physical = _close();
    _closePhysical = physical;
    physical.ignore();
    return physical;
  }

  Future<void> _close() async {
    try {
      // Native close must cancel/drain its I/O, so never queue it behind a read
      // or write that may be blocked by the external MCP client.
      if (await _invoke('close', null) != true) throw _unavailable();
      await Future.wait<void>([
        ready.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        if (_readPhysical case final read?) read,
        if (_writePhysical case final write?)
          write.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        if (_diagnosticPhysical case final diagnostic?) diagnostic,
      ]);
      unawaited(_input.close());
    } catch (_) {
      throw _unavailable();
    }
  }
}
