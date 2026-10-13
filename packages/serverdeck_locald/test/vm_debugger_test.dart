import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'support/vm_debugger.dart';

void main() {
  test(
    'failed and silent diagnostic RPCs preserve partial data and timeout log',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      WebSocket? socket;
      var failVm = false;
      final objectsRead = <String>[];
      final subscription = server.listen((request) async {
        socket = await WebSocketTransformer.upgrade(request);
        socket!.listen((message) {
          final rpc = jsonDecode(message as String) as Map;
          final method = rpc['method'];
          final isolate = (rpc['params'] as Map)['isolateId'];
          final objectId = (rpc['params'] as Map)['objectId'];
          if (method == 'getObject') {
            objectsRead.add(objectId as String);
            if (objectId == 'silent-trace') return;
          }
          if (isolate == 'worker')
            return; // All three RPCs retain real20s limits.
          final Object result = switch (method) {
            'getVM' => {
              'isolates': [
                {'id': 'main', 'name': 'main'},
                {'id': 'worker', 'name': 'worker'},
              ],
            },
            'getIsolate' => {
              'pauseEvent': {'kind': 'Resume'},
              'livePorts': 3,
              'pauseOnExit': false,
            },
            'getPorts' => {
              'ports': [
                {
                  'allocationLocation': {'kind': 'StackTrace', 'id': 'trace'},
                },
                {
                  'allocationLocation': {
                    'kind': 'String',
                    'id': 'private-payload',
                  },
                },
                {
                  'allocationLocation': {
                    'kind': 'StackTrace',
                    'id': 'silent-trace',
                  },
                },
              ],
            },
            'getObject' => {
              'kind': 'StackTrace',
              'valueAsString':
                  '#0 RawReceivePort (dart:isolate-patch/isolate_patch.dart:10:2)\n'
                  '#1 PortOwner.create (package:fixture/owner.dart:10:2)\n'
                  '#2 PortOwner.next (package:fixture/owner.dart:20:2)\n'
                  '#3 PortOwner.last (package:fixture/owner.dart:30:2)\n'
                  '#4 PortOwner.excess (package:fixture/owner.dart:40:2)\n'
                  'private-payload\nhttp://fixture-token/',
            },
            _ => {},
          };
          socket!.add(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': rpc['id'],
              if (method == 'getStack' || (method == 'getVM' && failVm))
                'error': {'code': -1, 'message': 'fixture RPC failure'}
              else
                'result': result,
            }),
          );
        });
      });
      final debugger = await VmDebugger.connect(
        Uri.parse('http://127.0.0.1:${server.port}/'),
      );
      try {
        final snapshots = await debugger.describePauses().timeout(
          const Duration(seconds: 30),
        );
        final main = snapshots.singleWhere((v) => v.name == 'main');
        expect(main.phase, 'Resume');
        expect(main.livePorts, 3);
        expect(main.receivePorts, 3);
        expect(main.pauseOnExit, false);
        expect(main.allocationFrames, hasLength(3));
        expect(main.allocationFrames.first, contains('PortOwner.create'));
        expect(main.allocationFrames.join('\n'), isNot(contains('excess')));
        expect(
          main.allocationFrames.join('\n'),
          isNot(contains('private-payload')),
        );
        expect(
          main.allocationFrames.join('\n'),
          isNot(contains('fixture-token')),
        );
        expect(objectsRead, unorderedEquals(['trace', 'silent-trace']));
        final worker = snapshots.singleWhere((v) => v.name == 'worker');
        expect(worker.phase, isNull);
        expect(worker.livePorts, isNull);
        expect(worker.receivePorts, isNull);
        failVm = true;
        final original = TimeoutException('VERIFIER_TIMEOUT');
        final logs = <String>[];
        Future<void> timeoutPath() async {
          try {
            throw original;
          } on TimeoutException {
            await debugger.reportTimeout([
              'WORKSPACE_CLOSE_END',
              'VERIFIER_MAIN_RETURNING',
              'http://fixture-token/',
            ], emit: logs.add);
            rethrow;
          }
        }

        await expectLater(timeoutPath(), throwsA(same(original)));
        expect(
          logs.join('\n'),
          contains('WORKSPACE_CLOSE_END\nVERIFIER_MAIN_RETURNING'),
        );
        expect(logs.join('\n'), isNot(contains('fixture-token')));
      } finally {
        await debugger.close();
        await socket?.close();
        await subscription.cancel();
        await server.close(force: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );
}
