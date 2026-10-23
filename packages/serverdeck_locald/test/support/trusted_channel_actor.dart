import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/trusted_server.dart';
import 'package:serverdeck_locald/api/trusted_channel.dart';
import 'package:serverdeck_locald/api/owner_profiles.dart';
import 'package:serverdeck_locald/api/trusted_owner_foundation.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/api/owner_trust_probes.dart';
import 'package:serverdeck_locald/bootstrap/trusted_services.dart';
import 'package:serverdeck_locald/remote/trust_probes.dart';
import 'package:serverdeck_locald/remote/ssh_transport.dart';
import 'package:serverdeck_locald/automation/profiles.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/mcp/profile_services.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_locald/mcp/router.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'trusted_auth_actor.dart' as n;
import 'trusted_grant_actor.dart' as g;
import 'mcp_runtime_actor.dart' as runtime;
import 'profile_catalog_actor.dart' show cleanupCatalogFixture;
import 'profile_catalog_storage_scenarios.dart' show catalogBody;

Map<String, Object?> data() => {
  'text': 'e\u0301😀',
  'counter': 9223372036854775807,
};

Map<String, Object?> depthData(String mode) {
  var value = <String, Object?>{'v': 0};
  for (var i = 0; i < (mode.contains('-over-') ? 12 : 11); i++) {
    value = {'v': value};
  }
  return value;
}

int wireDepth(Object? value) {
  final children = value is Map
      ? value.values
      : value is List
      ? value
      : const <Object?>[];
  var depth = 0;
  for (final child in children) {
    final candidate = wireDepth(child) + 1;
    if (candidate > depth) depth = candidate;
  }
  return depth;
}

bool ownerMode(String mode) => const {
  'trust-probes',
  'trust-writes',
  'foundation',
  'owner',
  'codes',
  'owner-blocked',
  'readiness-bad',
  'owner-builtin-errors',
  'backpressure',
  'rpc-timeout',
  'output-error',
}.contains(mode);
const ownerOnlyCodes = [
  'TRUST_REQUIRED',
  'TRUST_CHANGED',
  'HOST_BUSY',
  'AUTHENTICATION_FAILED',
  'CONNECTION_FAILED',
  'CANCELLED',
];
const ownerOnlyTransportCodes = SshTransportCode.values;
bool builtinErrors(String mode) =>
    mode == 'mcp-builtin-errors' || mode == 'owner-builtin-errors';
bool pendingMode(String mode) => const {
  'pending',
  'eof',
  'reentrant-close',
  'depth-pending',
  'depth-over-pending',
}.contains(mode);
Map<String, Object?> validationCall() => {
  'request': {
    'name': 'serverdeck_profiles_validate',
    'arguments': {
      'body': {
        'format': 1,
        'environment': 'ubuntu24.04-amd64-systemd',
        'parameters': <String, Object?>{},
        'steps': <Object?>[],
      },
    },
  },
};
Future<void> closed(Future<Object?> future) async {
  try {
    await future;
  } on StateError catch (error) {
    n.check(
      const {
        'EOF',
        'UNAUTHORIZED',
        'SERVICE_UNAVAILABLE',
      }.contains(error.message),
    );
    return;
  }
  throw StateError('EXPECTED_CLOSED');
}

final class Services implements TrustedMcpToolServices {
  Services(this.mode);
  final String mode;
  final pending = Completer<McpToolResult>();
  int calls = 0;
  Future<void> Function()? onCancel;
  McpToolResult output() => McpToolResult.success(
    mode.startsWith('depth-')
        ? depthData(mode)
        : mode == 'writer-revoke'
        ? {'large': 'x' * (1024 * 1024)}
        : data(),
  );
  @override
  McpServiceOperation start(
    TrustedMcpContext context,
    McpToolDefinition definition,
    Map<String, Object?> arguments,
  ) {
    calls++;
    return McpServiceOperation(
      pendingMode(mode)
          ? pending.future.then(
              (value) => mode.startsWith('depth-') ? output() : value,
            )
          : Future.sync(output),
      () async {
        await onCancel?.call();
      },
    );
  }
}

final class Owner implements TrustedOwnerApi {
  Owner(this.mode);
  final String mode;
  final gate = Completer<void>();
  int calls = 0, settled = 0;
  @override
  bool supports(String method) =>
      method == 'fixture.wait' || method == 'fixture.error';
  @override
  TrustedOwnerInvocation prepare(
    TrustedSessionRequest request,
    String method,
    Map<String, Object?> params, {
    required String requestId,
  }) {
    return TrustedOwnerInvocation(request, () async {
      if (method == 'fixture.error') {
        if (params['transport'] == true) {
          throw SshTransportFailure(
            SshTransportCode.values.byName(params['code'] as String),
          );
        }
        throw StateError(params['code'] as String);
      }
      final number = ++calls;
      if (mode == 'output-error') return {'invalid': Object()};
      await gate.future;
      settled++;
      return {'number': number};
    });
  }
}

final class Client {
  Client(this.session);
  final TrustedClientSession session;
  int counter = 0;
  int? bufferedSize;
  bool holdReplyTail = false;
  Future<Uint8List> fill(int count) async {
    final buffer = Uint8List(count);
    var offset = 0;
    while (offset < count) {
      final bytes = await session.peer.read(
        count: (count - offset).clamp(1, 65536),
        deadline: const Duration(seconds: 8),
      );
      if (bytes.isEmpty) throw StateError('EOF');
      n.check(bytes.length <= count - offset);
      buffer.setRange(offset, offset + bytes.length, bytes);
      offset += bytes.length;
      if (holdReplyTail &&
          count > 65536 &&
          count - offset > 0 &&
          count - offset <= 65536) {
        holdReplyTail = false;
        // Let the server's write complete with its final kernel-buffered tail
        // unread. Disconnect must not discard this already-issued frame tail.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    }
    return buffer;
  }

  Future<void> header() async {
    bufferedSize = ByteData.sublistView(await fill(4))
        .getUint32(0, Endian.little);
  }

  Future<Map<String, Object?>> read() async {
    final size =
        bufferedSize ??
        ByteData.sublistView(await fill(4)).getUint32(0, Endian.little);
    bufferedSize = null;
    n.check(size > 0 && size <= 8 * 1024 * 1024);
    final value = StrictCodec().decode(
      await fill(size),
      maxBytes: 8 * 1024 * 1024,
    );
    validateTrustedResponseEnvelope(value);
    n.check(value['generation'] == session.hello.generation);
    return value;
  }

  Future<String> send(
    String method,
    Map<String, Object?> params, {
    String? sessionId,
  }) async {
    final id =
        '52345678-1234-4234-8234-${(++counter).toString().padLeft(12, '0')}';
    await session.peer.write(
      frameBytes(
        encodeMcpMessage({
          'v': 1,
          'id': id,
          'sessionId': sessionId ?? session.id,
          'method': method,
          'params': params,
        }),
      ),
    );
    return id;
  }

  Future<Map<String, Object?>> call(
    String method,
    Map<String, Object?> params, {
    String? sessionId,
  }) async {
    final id = await send(method, params, sessionId: sessionId);
    final response = await read();
    n.check(response['id'] == id);
    return response;
  }
}

Future<void> client(List<String> args) async {
  final root = args[2], mode = args[3];
  runtime.ownRoot(root);
  final pipe = await PipeWorker.openTrustedClient(
    args[1],
    currentUserSid(),
    root,
  );
  if (mode == 'bootstrap-timeout') {
    final io = TrustedHandshakeIo(await pipe.verifyTrustedPeer());
    await io.read(() => const Duration(seconds: 8));
    final watch = Stopwatch()..start();
    await closed(io.read(() => const Duration(seconds: 8)));
    n.check(watch.elapsed >= const Duration(seconds: 4));
    await pipe.close();
    stdout.writeln('CLIENT_PASS');
    return;
  }
  final bootstrap = TrustedBootstrapClient(
    pipe: pipe,
    generation: n.generation,
    token: n.token,
  );
  try {
    final session = await bootstrap.authenticate();
    final rpc = Client(session);
    Future<void> done() async {
      await session.close();
      stdout.writeln('CLIENT_PASS');
    }

    final readiness = await rpc.call('readiness.get', {});
    if (builtinErrors(mode)) {
      var response = readiness;
      for (
        var i = 0;
        i < ownerOnlyCodes.length + ownerOnlyTransportCodes.length;
        i++
      ) {
        n.check((response['error'] as Map)['code'] == 'INTERNAL');
        n.check(
          ((await rpc.call('session.ping', {}))['result']
                  as Map)['leaseSeconds'] ==
              60,
        );
        response = await rpc.call('readiness.get', {});
      }
      n.check(
        TrustedReadiness.fromJson(response['result']).state ==
            ReadinessState.ready,
      );
      await rpc.call('session.close', {});
      await done();
      return;
    }
    if (mode == 'readiness-bad') {
      n.check((readiness['error'] as Map)['code'] == 'INTERNAL');
      n.check(
        ((await rpc.call('session.ping', {}))['result']
                as Map)['leaseSeconds'] ==
            60,
      );
      await rpc.call('session.close', {});
      await done();
      return;
    }
    final view = TrustedReadiness.fromJson(readiness['result']);
    n.check(view.generation == session.hello.generation && !view.features.any);
    n.check(
      view.state ==
          (mode == 'store-blocked' || mode == 'owner-blocked'
              ? ReadinessState.storageBlocked
              : ReadinessState.ready),
    );
    final denied = await rpc.call(
      ownerMode(mode) ? 'mcp.invoke' : 'grants.list',
      {},
    );
    n.check((denied['error'] as Map)['code'] == 'FORBIDDEN');
    final invalidReadiness = await rpc.call('readiness.get', {'extra': true});
    n.check((invalidReadiness['error'] as Map)['code'] == 'VALIDATION');
    if (mode == 'trust-writes') {
      final api = TrustedApiClient(session);
      const profile = '62345678-1234-4234-8234-000000090003';
      const operation = '62345678-1234-4234-8234-000000090004';
      const mutation = '62345678-1234-4234-8234-000000090006';
      Future<void> checkProfileReads(String revision) async {
        final got = await api.call('profiles.get', {'profileId': profile});
        final listed = await api.call('profiles.list', {});
        final item = got['profile'] as Map;
        final same = (listed['profiles'] as List).single as Map;
        n.check(
          jsonEncode(item) == jsonEncode(same) &&
              got['storeRevision'] == listed['storeRevision'] &&
              item['revision'] == revision &&
              item['connectionRevision'] == '1' &&
              item['credentialRevision'] == '1' &&
              item['trustRevision'] == revision,
        );
      }

      try {
        await checkProfileReads('1');
        try {
          await api.call('servers.trust.revoke', {
            'profileId': profile,
            'expectedRevision': '1',
          });
          throw StateError('EXPECTED_TRUST_REQUIRED');
        } on TrustedRpcException catch (error) {
          n.check(error.code == 'TRUST_REQUIRED');
        }
        await api.call('servers.trust.probe', {
          'profileId': profile,
          'expectedRevision': '1',
        }, requestId: operation);
        Map<String, Object?> status;
        final wait = Stopwatch()..start();
        do {
          n.check(wait.elapsed < const Duration(seconds: 5));
          status = await api.call('servers.trust.probeStatus', {
            'operationId': operation,
          });
          if (status['state'] == 'running')
            await Future<void>.delayed(const Duration(milliseconds: 5));
        } while (status['state'] == 'running');
        n.check(status['state'] == 'succeeded');
        final challenge = status['challenge'] as Map;
        final body = <String, Object?>{
          'profileId': profile,
          'expectedRevision': '1',
          'challengeId': challenge['challengeId'],
          'key': challenge['key'],
        };
        final confirmed = await api.call(
          'servers.trust.confirm',
          body,
          requestId: mutation,
        );
        n.check(confirmed['entityRevision'] == '2');
        await checkProfileReads('2');
        n.check(
          (await api.call('servers.trust.probeCancel', {
                'operationId': operation,
              }))['cancelled'] ==
              false,
        );
        final revoked = await api.call('servers.trust.revoke', {
          'profileId': profile,
          'expectedRevision': '2',
        });
        n.check(revoked['entityRevision'] == '3');
        await checkProfileReads('3');
        n.check(
          jsonEncode(
                await api.call(
                  'servers.trust.confirm',
                  body,
                  requestId: mutation,
                ),
              ) ==
              jsonEncode(confirmed),
        );
        final current = await api.call('servers.trust.get', {
          'profileId': profile,
        });
        n.check(
          current['trustRevision'] == '3' &&
              (current['trust'] as Map)['status'] == 'revoked',
        );
        final history = await api.call('mutations.get', {
          'requestId': mutation,
        });
        n.check(history['state'] == 'committed');
        n.check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
        await api.call('session.close', {});
      } finally {
        await api.close();
      }
      stdout.writeln('CLIENT_PASS');
      return;
    }
    if (mode == 'trust-probes') {
      final api = TrustedApiClient(session);
      const profile = '62345678-1234-4234-8234-000000090003';
      const operation = '62345678-1234-4234-8234-000000090004';
      try {
        n.check(
          (await api.call('servers.trust.get', {
                'profileId': profile,
              }))['trust'] ==
              null,
        );
        final body = {'profileId': profile, 'expectedRevision': '1'};
        n.check(
          (await api.call(
                'servers.trust.probe',
                body,
                requestId: operation,
              ))['operationId'] ==
              operation,
        );
        n.check(
          (await api.call(
                'servers.trust.probe',
                body,
                requestId: operation,
              ))['operationId'] ==
              operation,
        );
        final watch = Stopwatch()..start();
        Map<String, Object?> status;
        do {
          n.check(watch.elapsed < const Duration(seconds: 5));
          status = await api.call('servers.trust.probeStatus', {
            'operationId': operation,
          });
          if (status['state'] == 'running')
            await Future<void>.delayed(const Duration(milliseconds: 5));
        } while (status['state'] == 'running');
        n.check(
          status['state'] == 'failed' && status['code'] == 'CONNECTION_FAILED',
        );
        n.check(
          (await api.call('servers.trust.probeCancel', {
                'operationId': operation,
              }))['cancelled'] ==
              false,
        );
        try {
          await api.call('servers.trust.probe', {
            ...body,
            'expectedRevision': '2',
          }, requestId: operation);
          throw StateError('EXPECTED_CONFLICT');
        } on TrustedRpcException catch (error) {
          n.check(error.code == 'IDEMPOTENCY_CONFLICT');
        }
        n.check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
        await api.call('session.close', {});
      } finally {
        await api.close();
      }
      stdout.writeln('CLIENT_PASS');
      return;
    }
    if (mode == 'foundation') {
      final api = TrustedApiClient(session);
      try {
        const mutation = '62345678-1234-4234-8234-000000090001';
        const profile = '62345678-1234-4234-8234-000000090002';
        final current = await api.call('settings.get', {});
        final input = <String, Object?>{
          'expectedRevision': (current['settings'] as Map)['revision'],
          'theme': 'dark',
          'reduceMotion': true,
          'selectedProfileId': null,
        };
        final saved = await api.call(
          'settings.update',
          input,
          requestId: mutation,
        );
        n.check(
          jsonEncode(
                await api.call('settings.update', input, requestId: mutation),
              ) ==
              jsonEncode(saved),
        );
        n.check(
          (await api.call('mutations.get', {'requestId': mutation}))['state'] ==
              'committed',
        );
        final body = <String, Object?>{
          'profileId': profile,
          'name': 'Typed foundation wire',
          'address': 'wire.invalid',
          'port': 22,
          'sshUser': 'fixture',
          'tags': <String>[],
          'credential': {'action': 'remove'},
        };
        n.check(
          (await api.call('profiles.create', body))['entityRevision'] == '1',
        );
        n.check(
          ((await api.call('profiles.list', {}))['profiles'] as List).length ==
              1,
        );
        n.check(
          ((await api.call('profiles.get', {'profileId': profile}))['profile']
                  as Map)['trustRevision'] ==
              '1',
        );
        await api.call('profiles.update', {
          ...body,
          'expectedRevision': '1',
          'address': 'changed.invalid',
          'credential': {'action': 'keep'},
        });
        n.check(
          ((await api.call('profiles.get', {'profileId': profile}))['profile']
                  as Map)['trustRevision'] ==
              '2',
        );
        await api.call('profiles.delete', {
          'profileId': profile,
          'expectedRevision': '2',
        });
        n.check(
          ((await api.call('mutations.recent', {}))['receipts'] as List)
                  .length ==
              4,
        );
        n.check(
          ((await api.call('profiles.list', {}))['profiles'] as List).isEmpty,
        );
        await api.call('session.close', {});
      } finally {
        await api.close();
      }
      stdout.writeln('CLIENT_PASS');
      return;
    }
    if (const {
      'malformed',
      'duplicate',
      'oversize',
      'partial',
      'wrong-session',
    }.contains(mode)) {
      if (mode == 'wrong-session') {
        await closed(
          rpc.call(
            'session.ping',
            {},
            sessionId: base64Url.encode(List.filled(32, 7)).replaceAll('=', ''),
          ),
        );
      } else {
        final watch = Stopwatch()..start();
        if (mode == 'partial') {
          await session.peer.write([1, 2]);
        } else if (mode == 'oversize') {
          final header = ByteData(4)
            ..setUint32(0, 256 * 1024 + 1, Endian.little);
          await session.peer.write(header.buffer.asUint8List());
        } else if (mode == 'duplicate') {
          await session.peer.write(
            frameBytes(
              utf8.encode(
                '{"v":1,"id":"${g.requestId}","sessionId":"${session.id}","method":"session.ping","method":"session.close","params":{}}',
              ),
            ),
          );
        } else {
          await session.peer.write(frameBytes([255]));
        }
        await closed(rpc.read());
        if (mode == 'partial')
          n.check(watch.elapsed >= const Duration(seconds: 4));
      }
      await done();
      return;
    }
    if (!ownerMode(mode)) {
      final unopened = await rpc.call('mcp.invoke', {
        'catalog': <String, Object?>{},
      });
      n.check((unopened['error'] as Map)['code'] == 'FORBIDDEN');
      final invalidOpen = <String, Object?>{
        'grantId': g.grantId,
        'clientNonce': base64Url.encode(List.filled(32, 8)).replaceAll('=', ''),
        'proof': base64Url.encode(List.filled(32, 0)).replaceAll('=', ''),
      };
      if (mode == 'badproof') {
        final failed = await rpc.call('mcp.open', invalidOpen);
        n.check((failed['error'] as Map)['code'] == 'UNAUTHORIZED');
        await closed(rpc.call('session.ping', {}));
        await done();
        return;
      }
      if (mode == 'store-blocked') {
        await n.fails(
          session.openGrant(g.files(root), g.grantId),
          'STORAGE_BLOCKED',
        );
        await done();
        return;
      }
      if (mode == 'client-disconnect') {
        await n.fails(session.peer.disconnect(), 'UNSAFE_ENDPOINT');
      }
      await session.openGrant(g.files(root), g.grantId);
      if (mode == 'second-open') {
        await closed(rpc.call('mcp.open', invalidOpen));
        await done();
        return;
      }
      if (mode.startsWith('policy-') ||
          mode == 'native-failure' ||
          mode == 'worker-loss') {
        stdout.writeln('FAULT');
        await stdin.first;
        await closed(rpc.call('mcp.invoke', {'catalog': <String, Object?>{}}));
        await done();
        return;
      }
      final catalog = await rpc.call('mcp.invoke', {
        'catalog': <String, Object?>{},
      });
      n.check(
        ((catalog['result'] as Map)['tools'] as List).length ==
            (mode == 'all' ? 24 : 7),
      );
      final unknown = await rpc.call('mcp.invoke', {
        'request': {'name': 'NEVER_ECHO', 'arguments': <String, Object?>{}},
      });
      n.check(
        ((unknown['result'] as Map)['protocolError'] as Map)['code'] == -32602,
      );
      n.check(!jsonEncode(unknown).contains('NEVER_ECHO'));
      final union = await rpc.call('mcp.invoke', {
        'catalog': <String, Object?>{},
        'extra': true,
      });
      n.check((union['error'] as Map)['code'] == 'VALIDATION');
      if (mode == 'catalog') {
        Future<Map<String, Object?>> tool(
          String operation,
          Map<String, Object?> input,
        ) async {
          var envelope = await rpc.call('mcp.invoke', {
            'request': {
              'name': 'serverdeck_profiles_$operation',
              'arguments': input,
            },
          });
          var result = envelope['result'] as Map;
          final watch = Stopwatch()..start();
          while (result['done'] == false) {
            n.check(watch.elapsed < const Duration(seconds: 5));
            await Future<void>.delayed(const Duration(milliseconds: 5));
            envelope = await rpc.call('mcp.invoke', {
              'poll': {'operationId': result['operationId']},
            });
            result = envelope['result'] as Map;
          }
          final structured =
              (result['result'] as Map)['structuredContent'] as Map;
          n.check(structured['ok'] == true);
          return Map<String, Object?>.from(structured['data'] as Map);
        }

        var next = 0;
        String id() =>
            'a2345678-1234-4234-8234-${(++next).toString().padLeft(12, '0')}';
        final input = {
          'requestId': id(),
          'name': 'Wire catalog',
          'body': catalogBody(),
        };
        final created = await tool('create', input);
        final profile = created['profileId'] as String;
        n.check((await tool('create', input))['profileId'] == profile);
        n.check(((await tool('list', {}))['items'] as List).length == 1);
        n.check((await tool('get', {'profileId': profile}))['profile'] is Map);
        final update = {
          'requestId': id(),
          'profileId': profile,
          'expectedRevision': 1,
          'body': catalogBody(),
        };
        n.check((await tool('update', update))['revision'] == 2);
        n.check((await tool('update', update))['revision'] == 2);
        n.check(
          (await tool('compare', {
                'profileId': profile,
                'fromRevision': 1,
                'toRevision': 2,
              }))['changes']
              is List,
        );
        n.check(
          (await tool('validate', {'body': catalogBody()}))['valid'] == true,
        );
        await tool('archive', {
          'requestId': id(),
          'profileId': profile,
          'expectedRevision': 2,
        });
        n.check(
          ((await tool('get', {'profileId': profile}))['profile']
                  as Map)['archived'] ==
              true,
        );
        await rpc.call('mcp.close', {});
        await done();
        return;
      }
      if (mode == 'writer-revoke') {
        final first = await rpc.send('mcp.invoke', validationCall());
        await rpc.send('mcp.invoke', validationCall());
        await rpc.header();
        stdout.writeln('FAULT');
        await stdin.first;
        rpc.holdReplyTail = true;
        final published = await rpc.read();
        n.check(published['id'] == first);
        n.check(
          (((published['result'] as Map)['result'] as Map)['structuredContent']
                  as Map)['ok'] ==
              true,
        );
        await closed(rpc.read());
        await done();
        return;
      }
      var reply = await rpc.call('mcp.invoke', validationCall());
      if (mode == 'eof' || mode == 'reentrant-close') {
        n.check((reply['result'] as Map)['done'] == false);
        await done();
        return;
      }
      if (mode == 'pending' || mode.endsWith('-pending')) {
        final handle = (reply['result'] as Map)['operationId'];
        n.check(handle is String);
        stdout.writeln('PENDING');
        await stdin.first;
        reply = await rpc.call('mcp.invoke', {
          'poll': {'operationId': handle},
        });
        if (mode.startsWith('depth-')) {
          final repeated = await rpc.call('mcp.invoke', {
            'poll': {'operationId': handle},
          });
          n.check(
            jsonEncode(repeated['result']) == jsonEncode(reply['result']),
          );
        }
        final cancelled = await rpc.call('mcp.invoke', {
          'cancel': {'operationId': handle},
        });
        n.check((cancelled['result'] as Map)['cancelled'] == true);
      }
      final tool =
          ((reply['result'] as Map)['result'] as Map)['structuredContent']
              as Map;
      if (mode.startsWith('depth-')) {
        if (mode.contains('-over-')) {
          n.check(
            jsonEncode(tool) ==
                jsonEncode(
                  McpToolResult.failure('INTERNAL')
                      .toJson()['structuredContent'],
                ),
          );
        } else {
          n.check(jsonEncode(tool['data']) == jsonEncode(depthData(mode)));
          n.check(wireDepth(reply) == 16);
        }
      } else {
        n.check(jsonEncode(tool['data']) == jsonEncode(data()));
      }
    } else {
      final unknown = await rpc.call('grants.list', {});
      n.check((unknown['error'] as Map)['code'] == 'UNSUPPORTED');
      if (mode == 'owner-blocked') {
        final blocked = await rpc.call('fixture.wait', {
          'invalid': 'must not execute',
        });
        n.check((blocked['error'] as Map)['code'] == 'STORAGE_BLOCKED');
      } else if (mode == 'backpressure') {
        final ids = <String>{};
        final watch = Stopwatch()..start();
        var received = 0;
        try {
          for (var i = 0; i < 17; i++) {
            ids.add(await rpc.send('fixture.wait', {}));
          }
          stdout.writeln('SENT17');
          for (var i = 0; i < 17; i++) {
            n.check(ids.remove((await rpc.read())['id']));
            received++;
          }
          n.check(ids.isEmpty);
        } catch (_) {
          stderr.writeln(
            'BACKPRESSURE_RECEIVED:$received;ELAPSED_MS:${watch.elapsedMilliseconds}',
          );
          rethrow;
        }
      } else if (mode == 'rpc-timeout') {
        await rpc.send('fixture.wait', {});
        stdout.writeln('WAIT');
        final watch = Stopwatch()..start();
        await closed(rpc.read());
        n.check(watch.elapsed >= const Duration(seconds: 4));
        await done();
        return;
      } else if (mode == 'codes') {
        final api = TrustedApiClient(session);
        var completedCodes = 0;
        try {
          for (final code in TrustedLocalError.codes.where(
            (c) => c != 'UNAUTHORIZED',
          )) {
            try {
              await api.call('fixture.error', {'code': code});
              throw StateError('EXPECTED_DOMAIN_REFUSAL');
            } on TrustedRpcException catch (error) {
              n.check(
                !error.terminal &&
                    error.code == code &&
                    error.retry == TrustedLocalError(code).retry &&
                    error.field == null,
              );
            }
            n.check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
            stdout.writeln('CODES_PROGRESS:${++completedCodes}');
          }
          for (final code in SshTransportCode.values) {
            try {
              await api.call('fixture.error', {
                'code': code.name,
                'transport': true,
              });
              throw StateError('EXPECTED_TRANSPORT_REFUSAL');
            } on TrustedRpcException catch (error) {
              n.check(
                !error.terminal &&
                    error.code == TrustedLocalError.fromTransport(code).code,
              );
            }
            stdout.writeln('CODES_PROGRESS:${++completedCodes}');
          }
          try {
            await api.call('fixture.error', {
              'code': 'PRIVATE_UNEXPECTED_CODE',
            });
            throw StateError('EXPECTED_INTERNAL');
          } on TrustedRpcException catch (error) {
            n.check(!error.terminal && error.code == 'INTERNAL');
          }
          n.check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
          await api.call('session.close', {});
          await done();
          return;
        } finally {
          await api.close();
        }
      } else if (mode == 'output-error') {
        final invalid = await rpc.call('fixture.wait', {});
        n.check((invalid['error'] as Map)['code'] == 'INTERNAL');
      }
    }
    final closeAck = await rpc.call(
      ownerMode(mode) ? 'session.close' : 'mcp.close',
      {},
    );
    n.check((closeAck['result'] as Map)['closed'] == true);
    await done();
  } finally {
    await bootstrap.close();
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'client') {
      await n.client(args);
      return;
    }
    if (args.first == 'wire-client') {
      await client(args);
      return;
    }
    final mode = args[1];
    await g.scenario(
      args[0],
      'channel-$mode',
      readyRun: (root, store, authority, registry, write, advance) async {
        n.Pair? keeper;
        ReceiptKeyMaterial? key;
        TrustedAutomationProfileService? catalog;
        TrustedProfileOwnerApi? profileOwner;
        TrustedFoundationOwnerApi? foundationOwner;
        HostTrustProbeService? probes;
        SshTransportPool? probeTransports;
        TrustProbeOwnerApi? probeOwner;
        TrustedControlServices? control;
        Process? sshFixture;
        StreamIterator<String>? sshLines;
        Future<String>? sshErrors;
        Map? sshKey;
        try {
          if (mode == 'catalog' ||
              mode == 'foundation' ||
              mode == 'trust-probes' ||
              mode == 'trust-writes') {
            keeper = await n.Pair.start(
              root,
              'serverdeck.exe',
              registry,
              nativeGate: true,
            );
            registry = keeper.registry;
            await keeper.exchange();
            n.check(await keeper.next() == 'AUTH:owner');
            final custody = KeyCustody(DpapiProtection(), currentUserSid());
            final local = p.join(root, 'private');
            key = await custody.openReceiptKey(
              await readProtectedFile(
                local,
                p.join(
                  local,
                  'ServerDeckNext',
                  'v1',
                  'workspaces',
                  'default',
                  'receipt-key.dpapi',
                ),
                currentUserSid(),
                maxBytes: 16384,
              ),
              g.workspaceId,
              g.keyId,
            );
            if (mode == 'foundation' ||
                mode == 'trust-probes' ||
                mode == 'trust-writes') {
              foundationOwner = TrustedFoundationOwnerApi(
                store: store,
                coordinator: TrustedMutationCoordinator(store, custody, key),
                sessions: registry,
              );
              if (mode == 'trust-probes' || mode == 'trust-writes') {
                final socket = await ServerSocket.bind(
                  InternetAddress.loopbackIPv4,
                  0,
                );
                var port = socket.port;
                await socket.close();
                if (mode == 'trust-writes') {
                  final python =
                      Platform.environment['SERVERDECK_TRUST_FIXTURE_PYTHON'];
                  if (python == null)
                    throw StateError('TRUST_FIXTURE_PREREQUISITE');
                  sshFixture = await Process.start(python, [
                    '-I',
                    p.absolute('test/support/ssh_key_probe_server.py'),
                  ]);
                  sshErrors = sshFixture.stderr.transform(utf8.decoder).join();
                  sshLines = StreamIterator(
                    sshFixture.stdout
                        .transform(utf8.decoder)
                        .transform(const LineSplitter()),
                  );
                  n.check(
                    await sshLines.moveNext().timeout(
                      const Duration(seconds: 8),
                    ),
                  );
                  final metadata = jsonDecode(sshLines.current) as Map;
                  port = metadata['port'] as int;
                  sshKey = metadata['key'] as Map;
                }
                await foundationOwner.coordinator.submit(
                  '62345678-1234-4234-8234-000000090005',
                  ApiMethod.profilesCreate,
                  {
                    'profileId': '62345678-1234-4234-8234-000000090003',
                    'name': 'Wire probe',
                    'address': '127.0.0.1',
                    'port': port,
                    'sshUser': 'fixture',
                    'tags': <String>[],
                    'credential': {'action': 'remove'},
                  },
                  requester: 'fixture',
                );
                if (mode == 'trust-writes') {
                  await foundationOwner.close();
                  foundationOwner = null;
                  control = await TrustedControlServices.create(
                    store: store,
                    custody: custody,
                    receiptKey: key,
                    sessions: registry,
                  );
                  authority = control.authority;
                } else {
                  probeTransports = SshTransportPool();
                  probes = HostTrustProbeService(
                    store: store,
                    sessions: registry,
                    transports: probeTransports,
                  );
                  probeOwner = TrustProbeOwnerApi(probes);
                }
              }
            } else {
              catalog = TrustedAutomationProfileService(
                store: store,
                custody: custody,
                receiptKey: key,
                sessions: registry,
                authority: authority,
              );
              profileOwner = TrustedProfileOwnerApi(catalog);
            }
          }
          final services = Services(mode);
          final owner = Owner(mode);
          final router =
              control?.router ??
              TrustedMcpRouter(
                sessions: registry,
                authority: authority,
                services: catalog == null
                    ? services
                    : TrustedProfileCatalogMcpServices(catalog),
              );
          if (mode == 'store-blocked' || mode == 'owner-blocked')
            await store.close();
          var readinessCalls = 0;
          final server = TrustedApiServer(
            sessions: registry,
            authority: authority,
            router: router,
            owner:
                control ??
                (probeOwner == null
                    ? null
                    : TrustedOwnerApiGroup([foundationOwner!, probeOwner])) ??
                foundationOwner ??
                profileOwner ??
                (ownerMode(mode) && mode != 'owner' ? owner : null),
            readiness: () {
              if (builtinErrors(mode)) {
                final index = readinessCalls++;
                if (index < ownerOnlyCodes.length)
                  throw StateError(ownerOnlyCodes[index]);
                if (index <
                    ownerOnlyCodes.length + ownerOnlyTransportCodes.length) {
                  throw SshTransportFailure(
                    ownerOnlyTransportCodes[index - ownerOnlyCodes.length],
                  );
                }
              }
              return TrustedReadiness(
                state: store.isTrustedSnapshotLoaded
                    ? ReadinessState.ready
                    : ReadinessState.storageBlocked,
                generation: mode == 'readiness-bad' ? g.keyId : n.generation,
                workspaceId: g.workspaceId,
              );
            },
          );
          if (mode == 'basic') {
            final foreign = TrustedSessions(generation: n.generation);
            final otherAuthority = TrustedMcpAuthority(store);
            try {
              for (final mismatch in [false, true]) {
                var refused = false;
                try {
                  TrustedApiServer(
                    sessions: mismatch ? registry : foreign,
                    authority: mismatch ? otherAuthority : authority,
                    router: router,
                    readiness: () => TrustedReadiness(
                      state: ReadinessState.ready,
                      generation: n.generation,
                    ),
                  );
                } on ArgumentError {
                  refused = true;
                }
                n.check(refused);
              }
            } finally {
              otherAuthority.close();
              await foreign.close();
            }
          }
          final name = n.pipeName();
          final worker = await PipeWorker.createTrustedServer(
            name,
            currentUserSid(),
            root,
          );
          Process? child;
          TrustedServerChannel? channel;
          StreamIterator<String>? lines;
          try {
            final accepting = worker.accept();
            child = await Process.start(
              p.join(root, ownerMode(mode) ? 'serverdeck.exe' : 'mcp.exe'),
              ['wire-client', name, root, mode],
            );
            final errors = child.stderr.transform(utf8.decoder).join();
            lines = StreamIterator(
              child.stdout
                  .transform(utf8.decoder)
                  .transform(const LineSplitter()),
            );
            await accepting;
            final handshake = TrustedServerHandshake(
              peer: await worker.verifyTrustedPeer(),
              token: n.token,
              channel: name,
              sessions: registry,
            );
            channel = TrustedServerChannel(
              handshake: handshake,
              server: server,
            );
            if (mode == 'reentrant-close') {
              services.onCancel = () async {
                final first = channel!.close();
                n.check(identical(first, channel.close()));
                await first;
              };
            }
            final running = channel.run();
            running.ignore();
            final codesWatch = Stopwatch()..start();
            var completedCodes = 0;
            var began = await lines.moveNext().timeout(
              const Duration(seconds: 12),
            );
            while (mode == 'codes' &&
                began &&
                lines.current.startsWith('CODES_PROGRESS:')) {
              n.check(
                completedCodes < 28 &&
                    lines.current == 'CODES_PROGRESS:${++completedCodes}',
              );
              began = await lines.moveNext().timeout(
                const Duration(seconds: 12),
              );
            }
            if (mode == 'codes') {
              n.check(completedCodes == 28);
              stdout.writeln(
                'CODES_VERIFIED:$completedCodes;ELAPSED_MS:${codesWatch.elapsedMilliseconds}',
              );
            }
            if (!began) stderr.write(await errors);
            n.check(began);
            if (mode == 'pending' || mode.endsWith('-pending')) {
              n.check(lines.current == 'PENDING');
              services.pending.complete(McpToolResult.success(data()));
              child.stdin.writeln('release');
              n.check(await lines.moveNext());
            }
            if (mode.startsWith('policy-') ||
                mode == 'native-failure' ||
                mode == 'worker-loss' ||
                mode == 'writer-revoke') {
              n.check(lines.current == 'FAULT');
              if (mode == 'writer-revoke') {
                final watch = Stopwatch()..start();
                while (channel.pendingPublications < 2) {
                  n.check(watch.elapsed < const Duration(seconds: 3));
                  await Future<void>.delayed(const Duration(milliseconds: 5));
                }
                n.check(services.calls == 2);
              }
              if (mode == 'worker-loss') {
                await worker.close();
              } else if (mode == 'policy-expiry') {
                advance(const Duration(seconds: 300));
              } else if (mode == 'native-failure') {
                runtime.manifest(
                  root,
                  (m) => (m['sha256'] as Map)['mcp.exe'] = '0' * 64,
                );
              } else {
                await write(
                  mode == 'policy-replace' ? 'grant.replace' : 'grant.revoke',
                );
              }
              child.stdin.writeln('release');
              final continued = await lines.moveNext().timeout(
                const Duration(seconds: 12),
              );
              // This child is an owned synthetic fixture emitting fixed codes
              // and bounded stack frames only. Preserve its failure evidence.
              if (!continued) stderr.write(await errors);
              n.check(continued);
            }
            if (mode == 'backpressure') {
              n.check(lines.current == 'SENT17');
              final watch = Stopwatch()..start();
              while (owner.calls < 16) {
                n.check(watch.elapsed < const Duration(seconds: 3));
                await Future<void>.delayed(const Duration(milliseconds: 5));
              }
              n.check(owner.calls == 16 && channel.activeRequests == 16);
              await Future<void>.delayed(const Duration(milliseconds: 30));
              n.check(owner.calls == 16);
              owner.gate.complete();
              final continued = await lines.moveNext().timeout(
                const Duration(seconds: 12),
              );
              if (!continued) stderr.write(await errors);
              n.check(continued);
            } else if (mode == 'rpc-timeout') {
              n.check(lines.current == 'WAIT');
              n.check(
                await lines.moveNext().timeout(const Duration(seconds: 12)),
              );
            }
            n.check(lines.current == 'CLIENT_PASS');
            await n.finishClient(child);
            n.check(await child.exitCode == 0 && (await errors).isEmpty);
            if (mode == 'worker-loss') {
              await n.fails(
                running.timeout(const Duration(seconds: 10)),
                'SERVICE_UNAVAILABLE',
              );
              final first = channel.close();
              n.check(identical(first, channel.close()));
              await n.fails(first, 'SERVICE_UNAVAILABLE');
            } else {
              await running.timeout(const Duration(seconds: 10));
            }
            n.check(
              registry.count ==
                      (mode == 'catalog' ||
                              mode == 'foundation' ||
                              mode == 'trust-probes' ||
                              mode == 'trust-writes'
                          ? 1
                          : 0) &&
                  router.retainedOperations == 0,
            );
            if (mode == 'eof' || mode == 'reentrant-close') {
              n.check(router.chargedOperations == 1);
              services.pending.complete(McpToolResult.success(data()));
              await Future<void>.delayed(const Duration(milliseconds: 20));
              n.check(router.chargedOperations == 0);
            }
            if (mode == 'owner-blocked') n.check(owner.calls == 0);
            if (mode == 'backpressure')
              n.check(owner.calls == 17 && owner.settled == 17);
            if (mode == 'rpc-timeout') {
              n.check(owner.calls == 1 && owner.settled == 0);
              owner.gate.complete();
              await Future<void>.delayed(const Duration(milliseconds: 20));
              n.check(owner.settled == 1 && registry.count == 0);
            }
          } finally {
            if (!owner.gate.isCompleted) owner.gate.complete();
            if (!services.pending.isCompleted)
              services.pending.complete(McpToolResult.success(data()));
            if (mode == 'worker-loss' && channel != null) {
              await n.fails(channel.close(), 'SERVICE_UNAVAILABLE');
            } else {
              await channel?.close();
            }
            router.close();
            child?.kill();
            if (child != null) await child.exitCode;
            await lines?.cancel();
            await worker.close();
          }
          if (mode == 'catalog') {
            n.check(
              store
                      .trustedOperational
                      .automation
                      .profiles
                      .values
                      .single
                      .archived &&
                  store.trustedOperational.automation.revisions.length == 2,
            );
          }
        } finally {
          await cleanupCatalogFixture([
            () async => control?.close(),
            () async => probes?.close(),
            () async => probeTransports?.close(),
            () async => foundationOwner?.close(),
            () async => profileOwner?.close(),
            () async => catalog?.close(),
            () async {
              if (keeper != null) await registry.close();
            },
            () async => keeper?.close(),
            () async {
              final process = sshFixture, lines = sshLines;
              if (process == null || lines == null) return;
              try {
                process.stdin.writeln('stats');
                n.check(
                  await lines.moveNext().timeout(const Duration(seconds: 3)),
                );
                final stats = jsonDecode(lines.current) as Map;
                n.check(stats['authentication'] == 0 && stats['accepted'] == 1);
                final row = store
                    .trustedOperational
                    .foundation
                    .trust['62345678-1234-4234-8234-000000090003']!;
                n.check(jsonEncode(row.key.toJson()) == jsonEncode(sshKey));
              } finally {
                process.stdin.writeln('close');
                await process.stdin.close();
                try {
                  await process.exitCode.timeout(const Duration(seconds: 5));
                } on TimeoutException {
                  process.kill();
                  await process.exitCode;
                }
                await sshLines?.cancel();
                n.check((await sshErrors!).isEmpty);
              }
            },
            () async => key?.close(),
          ]);
        }
      },
    );
    stdout.writeln('PASS:$mode');
  } catch (error, stack) {
    stderr.writeln('CHANNEL_FIXTURE_FAILED');
    if (error is StateError &&
        const {
          'TIMEOUT',
          'EOF',
          'UNAUTHORIZED',
          'SERVICE_UNAVAILABLE',
          'FIXTURE_ASSERTION',
          'RESOURCE_LIMIT',
        }.contains(error.message)) {
      stderr.writeln(error.message);
    } else if (error is FormatException) {
      stderr.writeln('INVALID_FRAME');
    }
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
