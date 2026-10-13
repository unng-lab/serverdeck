import 'dart:async';
import 'dart:convert';
import 'dart:io';

typedef VmPauseSnapshot = ({
  String name,
  String? phase,
  int? livePorts,
  bool? pauseOnExit,
  int? receivePorts,
  List<String> allocationFrames,
});

/// Test-only VM service client. No runtime dependency or production failpoint.
class VmDebugger {
  VmDebugger._(this._socket) {
    _subscription = _socket.listen(
      (message) {
        final value = jsonDecode(message as String) as Map<String, dynamic>;
        if (value.containsKey('id')) {
          final pending = _pending.remove(value['id']);
          if (value.containsKey('error')) {
            pending?.completeError(StateError('VM_RPC_${value['error']}'));
          } else {
            pending?.complete(value['result'] as Map<String, dynamic>);
          }
        } else if (value['method'] == 'streamNotify') {
          _events.add(value['params']['event'] as Map<String, dynamic>);
        }
      },
      onError: (Object error) => _fail(error),
      onDone: () => _fail(StateError('VM_CONNECTION_CLOSED')),
    );
  }
  final WebSocket _socket;
  late final StreamSubscription<dynamic> _subscription;
  final _pending = <String, Completer<Map<String, dynamic>>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  int _next = 0;
  final observedExceptions = <String>[];
  static Future<VmDebugger> connect(Uri uri) async {
    final socketUri = uri.replace(scheme: 'ws', path: '${uri.path}ws');
    return VmDebugger._(
      await WebSocket.connect(socketUri.toString())
          .timeout(const Duration(seconds: 15)),
    );
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, Object?> parameters = const {},
    Duration timeout = const Duration(seconds: 20),
  ]) async {
    final id = '${++_next}', result = Completer<Map<String, dynamic>>();
    _pending[id] = result;
    _socket.add(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': parameters,
      }),
    );
    try {
      return await result.future.timeout(timeout);
    } finally {
      _pending.remove(id);
    }
  }

  Future<Map<String, dynamic>> paused(String breakpointId) => _events.stream
      .firstWhere(
        (event) =>
            event['kind'] == 'PauseBreakpoint' &&
            (event['pauseBreakpoints'] as List? ?? []).any(
              (value) => value['id'] == breakpointId,
            ),
      )
      .timeout(const Duration(seconds: 30));

  /// Startup fixtures have no profile secrets. Inspect only error messages and
  /// source locations; never inspect locals or arbitrary application objects.
  Future<Map<String, dynamic>> tracedPause(
    String isolateId,
    String breakpointId,
  ) => _events.stream
      .asyncMap((event) => _trace(event, isolateId))
      .firstWhere(
        (event) =>
            event['kind'] == 'PauseBreakpoint' &&
            (event['pauseBreakpoints'] as List? ?? []).any(
              (value) => value['id'] == breakpointId,
            ),
      )
      .timeout(const Duration(seconds: 45));

  Future<int> tracedExit(String isolateId, Future<int> exit) async {
    final failed = Completer<int>();
    final subscription = _events.stream
        .asyncMap((event) => _trace(event, isolateId))
        .listen(
          (_) {},
          onError: (Object error, StackTrace stack) {
            if (!failed.isCompleted) failed.completeError(error, stack);
          },
        );
    try {
      return await Future.any([exit, failed.future]);
    } finally {
      await subscription.cancel();
    }
  }

  Future<Map<String, dynamic>> _trace(
    Map<String, dynamic> event,
    String isolateId,
  ) async {
    if (event['kind'] == 'PauseException' &&
        event['isolate']['id'] == isolateId) {
      final exception = await call('getObject', {
        'isolateId': isolateId,
        'objectId': event['exception']['id'],
      });
      final type = exception['class']['name'];
      final fields = (exception['fields'] as List? ?? []).cast<Map>();
      final messages = fields
          .where((v) => v['decl']['name'] == 'message')
          .toList();
      String? message;
      if (messages.isNotEmpty) {
        final value = messages.first['value']['valueAsString'];
        if (value is String &&
            (type == 'IsarError' || RegExp(r'^[A-Z_0-9]+$').hasMatch(value)))
          message = value;
      }
      stderr.writeln(
        'INIT_EXCEPTION_TYPE_$type${message == null ? '' : ':$message'}',
      );
      if (observedExceptions.length < 16)
        observedExceptions.add(message ?? '$type');
      if (type == 'FileSystemException') {
        final osErrors = fields
            .where((v) => v['decl']['name'] == 'osError')
            .toList();
        if (osErrors.isNotEmpty && osErrors.first['value']['id'] is String) {
          final os = await call('getObject', {
            'isolateId': isolateId,
            'objectId': osErrors.first['value']['id'],
          });
          for (final field in (os['fields'] as List? ?? []).cast<Map>()) {
            final name = field['decl']['name'],
                value = field['value']['valueAsString'];
            if (name == 'errorCode' ||
                (name == 'message' &&
                    value is String &&
                    RegExp(r'^[A-Z_]+$').hasMatch(value))) {
              stderr.writeln('INIT_OS_ERROR_$name:$value');
            }
          }
        }
      }
      final stack = await call('getStack', {'isolateId': isolateId});
      for (final frame in (stack['frames'] as List).cast<Map>().take(5)) {
        stderr.writeln(
          'INIT_EXCEPTION_FRAME_${frame['function']['name']}:${frame['location']['script']['uri']}:${frame['location']['tokenPos']}',
        );
      }
      await call('resume', {'isolateId': isolateId});
    }
    return event;
  }

  Future<List<VmPauseSnapshot>> describePauses({String? isolateId}) async {
    final vm = await _diagnosticCall('getVM');
    if (vm == null) return [];
    return Future.wait(
      (vm['isolates'] as List)
          .cast<Map>()
          .where(
            (reference) => isolateId == null || reference['id'] == isolateId,
          )
          .map((reference) async {
            final parameters = <String, Object?>{'isolateId': reference['id']};
            final results = await Future.wait([
              _diagnosticCall('getIsolate', parameters),
              _diagnosticCall('getPorts', parameters),
              _diagnosticCall('getStack', parameters),
            ]);
            final isolate = results[0];
            final allocations = await Future.wait([
              for (final port in (results[1]?['ports'] as List? ?? []).take(4))
                _portAllocationFrames(reference['id'] as String, port as Map),
            ]);
            final snapshot = (
              name: reference['name'] as String,
              phase: isolate?['pauseEvent']?['kind'] as String?,
              livePorts: isolate?['livePorts'] as int?,
              pauseOnExit: isolate?['pauseOnExit'] as bool?,
              receivePorts: (results[1]?['ports'] as List?)?.length,
              allocationFrames: allocations.expand((v) => v).toList(),
            );
            stderr.writeln(
              'INIT_ISOLATE_${snapshot.name}:${snapshot.phase}:livePorts=${snapshot.livePorts}:pauseOnExit=${snapshot.pauseOnExit}:receivePorts=${snapshot.receivePorts}',
            );
            for (final frame in snapshot.allocationFrames) {
              stderr.writeln('INIT_PORT_ALLOCATION_$frame');
            }
            // Read only allocation StackTrace references, never port fields,
            // handlers, messages, or arbitrary application objects/locals.
            final stack = results[2];
            for (final frame
                in (stack?['frames'] as List? ?? []).cast<Map>().take(3)) {
              stderr.writeln(
                'INIT_WAIT_FRAME_${frame['function']['name']}:${frame['location']['script']['uri']}:${frame['location']['tokenPos']}',
              );
            }
            return snapshot;
          }),
    );
  }

  Future<List<String>> _portAllocationFrames(String isolateId, Map port) async {
    final location = port['allocationLocation'];
    if (location is! Map ||
        location['kind'] != 'StackTrace' ||
        location['id'] is! String)
      return [];
    final trace = await _diagnosticCall('getObject', {
      'isolateId': isolateId,
      'objectId': location['id'],
    }, const Duration(seconds: 2));
    if (trace?['kind'] != 'StackTrace' || trace?['valueAsString'] is! String)
      return [];
    // Source frames only; ignore headers, tokens, URLs, and port payloads.
    final framePattern = RegExp(
      r'^#\d+\s+[A-Za-z0-9_.$<> ]+\s+\((?:dart:|package:|file:///)[^\r\n]+:\d+:\d+\)$',
    );
    return (trace!['valueAsString'] as String)
        .split('\n')
        .map((value) => value.trim())
        .where(
          (value) =>
              value.length <= 512 &&
              framePattern.hasMatch(value) &&
              !value.contains('http://') &&
              !value.contains('https://') &&
              !value.contains('dart:isolate-patch/isolate_patch.dart'),
        )
        .take(3)
        .toList();
  }

  Future<Map<String, dynamic>?> _diagnosticCall(
    String method, [
    Map<String, Object?> parameters = const {},
    Duration timeout = const Duration(seconds: 20),
  ]) async {
    try {
      return await call(method, parameters, timeout);
    } catch (_) {
      stderr.writeln('INIT_DIAGNOSTIC_UNAVAILABLE_$method');
      return null;
    }
  }

  /// Diagnostics must never replace the caller's original verifier exception.
  Future<void> reportTimeout(
    List<String> verificationLog, {
    void Function(String)? emit,
  }) async {
    final write = emit ?? stderr.writeln;
    try {
      await describePauses();
    } catch (_) {
      write('INIT_DIAGNOSTIC_UNAVAILABLE');
    } finally {
      write(verificationLog.where((v) => !v.contains('http://')).join('\n'));
    }
  }

  void _fail(Object error) {
    for (final value in _pending.values) {
      if (!value.isCompleted) value.completeError(error);
    }
    _pending.clear();
  }

  Future<void> close() async {
    await _subscription.cancel();
    await _socket.close().timeout(const Duration(seconds: 5));
    _fail(StateError('VM_CONNECTION_CLOSED'));
    await _events.close();
  }
}
