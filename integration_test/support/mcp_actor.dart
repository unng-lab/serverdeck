import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Private control pipe to an independent Python client. Neither actor imports
/// ServerDeck internals; its child speaks MCP to the real bundle executable.
/// Diagnostics deliberately never include received documents or child output.
final class IndependentMcpActor {
  IndependentMcpActor._(this._process, this._markers, this._expectedClient) {
    _ready.future.ignore();
    _output = _process.stdout.listen(
      _bytes,
      onError: (Object _) => _fail('MCP_ACTOR_IO'),
      onDone: () {
        if (!_closing) _fail('MCP_ACTOR_EOF');
        _stdoutDone.complete();
      },
    );
    _diagnostics = _process.stderr.listen(
      _diagnosticBytes,
      onError: (Object _) => _fail('MCP_ACTOR_IO'),
      onDone: () => _stderrDone.complete(),
    );
    _exit = _process.exitCode;
    _exit.then((_) {
      if (!_closing) _fail('MCP_ACTOR_EXIT');
    });
  }

  final Process _process;
  final List<String> _markers;
  final String _expectedClient;
  late final StreamSubscription<List<int>> _output, _diagnostics;
  late final Future<int> _exit;
  final _ready = Completer<void>();
  final _stdoutDone = Completer<void>(), _stderrDone = Completer<void>();
  final _line = <int>[];
  final _diagnosticTail = <int>[];
  Completer<Map<String, Object?>>? _reply;
  String? _pendingId, _failure;
  int _serial = 0, _diagnosticCount = 0;
  bool _closing = false;
  Future<void>? _closed;
  static const _limit = 8 * 1024 * 1024;

  static Future<IndependentMcpActor> start({
    required String python,
    required String repository,
    required String fixtureRoot,
    required String grantId,
    required bool sdk,
    required List<String> secretMarkers,
  }) async {
    if (!Platform.isWindows ||
        !File(python).isAbsolute ||
        !Directory(repository).isAbsolute ||
        !Directory(fixtureRoot).isAbsolute ||
        secretMarkers.length > 32 ||
        secretMarkers.any((m) => m.length < 8 || m.length > 4096)) {
      throw StateError('MCP_ACTOR_CONFIGURATION');
    }
    final actor = IndependentMcpActor._(
      await Process.start(
        python,
        [
          '-I',
          // -I excludes the script directory from sys.path. The fixed loader
          // adds only the repository actor directory, not caller Python paths.
          '$repository/tools/mcp_clients/launch.py',
          sdk ? 'sdk' : 'wire',
        ],
        workingDirectory: fixtureRoot,
        environment: {'LOCALAPPDATA': '$fixtureRoot/profile'},
        mode: ProcessStartMode.normal,
      ),
      List.unmodifiable(secretMarkers),
      sdk ? 'official-sdk-2.0.0' : 'stdlib-wire',
    );
    try {
      await actor._send({
        'command': '$fixtureRoot/application bundle/mcp.exe',
        'args': [
          '--app-root',
          '$fixtureRoot/application bundle',
          '--grant-id',
          grantId,
        ],
        'markers': secretMarkers,
      });
      await actor._ready.future.timeout(const Duration(seconds: 45));
      return actor;
    } on Object {
      await actor._terminate();
      throw StateError('MCP_ACTOR_STARTUP');
    }
  }

  void _fail(String code) {
    _failure ??= code;
    if (!_ready.isCompleted) _ready.completeError(StateError(code));
    final reply = _reply;
    if (reply != null && !reply.isCompleted) {
      reply.completeError(StateError(code));
    }
  }

  void _scan(List<int> bytes) {
    // JSON escapes are checked again after decoding; stderr is also checked
    // across arbitrary OS chunk boundaries without retaining whole diagnostics.
    final text = utf8.decode(bytes, allowMalformed: true);
    if (_markers.any(text.contains)) throw StateError('MCP_ACTOR_SECRET_LEAK');
  }

  void _diagnosticBytes(List<int> bytes) {
    try {
      _diagnosticCount += bytes.length;
      if (_diagnosticCount > 256 * 1024) {
        throw StateError('MCP_ACTOR_LIMIT');
      }
      _diagnosticTail.addAll(bytes);
      _scan(_diagnosticTail);
      // At most 4096 Unicode scalars, each up to four UTF-8 bytes.
      if (_diagnosticTail.length > 16384) {
        _diagnosticTail.removeRange(0, _diagnosticTail.length - 16384);
      }
    } on Object {
      _fail('MCP_ACTOR_DIAGNOSTICS');
    }
  }

  void _bytes(List<int> bytes) {
    try {
      for (final byte in bytes) {
        if (byte != 10) {
          if (_line.length >= _limit) throw StateError('MCP_ACTOR_LIMIT');
          _line.add(byte);
          continue;
        }
        _scan(_line);
        final value = jsonDecode(utf8.decode(_line));
        _line.clear();
        _scan(utf8.encode(jsonEncode(value)));
        _scanDecoded(value);
        if (value is! Map<String, dynamic>) {
          throw StateError('MCP_ACTOR_PROTOCOL');
        }
        if (!_ready.isCompleted) {
          if (value['ready'] != true ||
              value['client'] != _expectedClient ||
              value['protocolVersion'] != '2025-11-25') {
            throw StateError('MCP_ACTOR_PROTOCOL');
          }
          _ready.complete();
        } else {
          final reply = _reply;
          if (reply == null ||
              reply.isCompleted ||
              value['jsonrpc'] != '2.0' ||
              value['id'] != _pendingId ||
              value.containsKey('result') == value.containsKey('error')) {
            throw StateError('MCP_ACTOR_PROTOCOL');
          }
          reply.complete(Map<String, Object?>.from(value));
        }
      }
    } on Object {
      _fail('MCP_ACTOR_PROTOCOL');
    }
  }

  void _scanDecoded(Object? value, [int depth = 0]) {
    if (depth > 64) throw StateError('MCP_ACTOR_LIMIT');
    if (value is String && _markers.any(value.contains)) {
      throw StateError('MCP_ACTOR_SECRET_LEAK');
    }
    if (value is List) {
      for (final entry in value) {
        _scanDecoded(entry, depth + 1);
      }
    } else if (value is Map) {
      for (final entry in value.entries) {
        _scanDecoded(entry.key, depth + 1);
        _scanDecoded(entry.value, depth + 1);
      }
    }
  }

  Future<void> _send(Map<String, Object?> value) async {
    final bytes = utf8.encode('${jsonEncode(value)}\n');
    if (bytes.length > 256 * 1024) throw StateError('MCP_ACTOR_LIMIT');
    _process.stdin.add(bytes);
    await _process.stdin.flush().timeout(const Duration(seconds: 5));
  }

  Future<Map<String, Object?>> call(
    String method, [
    Map<String, Object?> params = const {},
  ]) async {
    if (_closing ||
        _failure != null ||
        _reply != null ||
        !const {'tools/list', 'tools/call', 'ping'}.contains(method)) {
      throw StateError('MCP_ACTOR_UNAVAILABLE');
    }
    final id = 'case-${++_serial}';
    final reply = Completer<Map<String, Object?>>();
    // Attach an error listener before the potentially asynchronous write.
    final response = reply.future.timeout(const Duration(seconds: 50));
    response.ignore();
    _reply = reply;
    _pendingId = id;
    try {
      await _send({'id': id, 'method': method, 'params': params});
      return await response;
    } on Object {
      _fail('MCP_ACTOR_CALL');
      throw StateError('MCP_ACTOR_CALL');
    } finally {
      _reply = null;
      _pendingId = null;
    }
  }

  Future<void> close() => _closed ??= _close();
  Future<void> _close() async {
    if (_reply != null) throw StateError('MCP_ACTOR_PENDING');
    // Keep scanning until both actual pipes reach EOF. Only EOF/exit during
    // this intentional close is expected; parse/secret failures still count.
    _closing = true;
    try {
      await _process.stdin.close().timeout(const Duration(seconds: 5));
      final code = await _exit.timeout(const Duration(seconds: 15));
      await Future.wait([_stdoutDone.future, _stderrDone.future])
          .timeout(const Duration(seconds: 5));
      if (code != 0 || _failure != null || _line.isNotEmpty) {
        throw StateError('MCP_ACTOR_SHUTDOWN');
      }
    } on Object {
      await _terminate();
      throw StateError('MCP_ACTOR_SHUTDOWN');
    }
  }

  Future<void> _terminate() async {
    _closing = true;
    try {
      // Let the independent client close its stdio child on EOF first.
      try {
        await _process.stdin.close().timeout(const Duration(seconds: 3));
      } on Object {
        // Broken input can also mean the actor is already exiting.
      }
      try {
        await _exit.timeout(const Duration(seconds: 15));
      } on Object {
        // Only the retained actor may be killed. This does not prove cleanup
        // of its child and cannot become a passing acceptance result.
        _process.kill();
        await _exit.timeout(const Duration(seconds: 5));
        throw StateError('MCP_ACTOR_TERMINATION');
      }
    } finally {
      await Future.wait([_output.cancel(), _diagnostics.cancel()]);
    }
  }
}
