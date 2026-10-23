import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/host_trust.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/readiness.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_protocol/protocol.dart';
import 'package:serverdeck_windows/operational_auth_client.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/pipe_worker.dart';
import 'package:serverdeck_windows/security.dart';

import 'native_fixture_job.dart';
import 'client_cleanup_fixture.dart' as cleanup;

const generation = '10000000-0000-4000-8000-000000000001';
const workspace = '10000000-0000-4000-8000-000000000002';
const grantId = '10000000-0000-4000-8000-000000000003';
const connectionBadMethods = {
  'bad-connection': 'servers.connection',
  'bad-connect': 'servers.connect',
  'bad-connect-status': 'servers.connectStatus',
  'bad-connect-cancel': 'servers.connectCancel',
  'bad-disconnect': 'servers.disconnect',
};
Map<String, Object?> connectionResult(String method) {
  final connected = <String, Object?>{
    'profileId': workspace,
    'state': 'connected',
    'interested': true,
    'identity': {
      'profileId': workspace,
      'connectionRevision': '1',
      'credentialRevision': '3',
      'trustRevision': '2',
      'key': {
        'format': 'ssh-ed25519',
        'fingerprint':
            'SHA256:${base64.encode(List.filled(32, 7)).replaceAll('=', '')}',
      },
    },
  };
  return switch (method) {
    'servers.connection' => connected,
    'servers.connect' => {'operationId': grantId, 'state': 'running'},
    'servers.connectStatus' => {
      'operationId': grantId,
      'state': 'succeeded',
      'connection': connected,
    },
    'servers.connectCancel' => {'operationId': grantId, 'cancelled': false},
    'servers.disconnect' => {
      'profileId': workspace,
      'state': 'disconnected',
      'interested': false,
      'identity': null,
    },
    _ => throw StateError('UNSUPPORTED'),
  };
}

McpCredentialFiles files(String root) => McpCredentialFiles(
  localAppData: p.join(root, 'private'),
  workspaceId: workspace,
  ownerSid: currentUserSid(),
  custody: McpCredentialCustody(DpapiProtection()),
);
final token = List<int>.generate(32, (i) => i);
String nonce([int n = 0]) =>
    base64Url.encode(List.filled(32, n)).replaceAll('=', '');
void check(bool value) {
  if (!value) throw StateError('TRUSTED_CLIENT_FIXTURE_FAILED');
}

String mac(List<int> bytes) {
  final key = SecretKeyData(List.of(token), overwriteWhenDestroyed: true);
  try {
    return base64Url
        .encode(
          DartHmac.sha256()
              .calculateMacSync(bytes, secretKeyData: key, nonce: const [])
              .bytes,
        )
        .replaceAll('=', '');
  } finally {
    key.destroy();
  }
}

Future<void> domain(
  Future<Object?> action,
  String code, {
  required bool terminal,
}) async {
  try {
    await action;
  } on TrustedRpcException catch (e) {
    check(e.code == code && e.terminal == terminal);
    return;
  }
  throw StateError('EXPECTED_TRUSTED_RPC_ERROR');
}

Map<String, Object?> recent() => {
  'receipts': [
    for (var i = 0; i < 2; i++)
      {
        'requestId': '20000000-0000-4000-8000-00000000000${i + 1}',
        'operation': i == 0 ? 'servers.trust.confirm' : 'servers.trust.revoke',
        'profileId': workspace,
        'result': {
          'entityId': workspace,
          'entityRevision': '${3 - i}',
          'storeRevision': '${3 - i}',
          'deleted': false,
        },
        'committedAt': '2026-10-22T00:00:00.000Z',
      },
  ],
  'truncated': false,
};

Future<void> client(List<String> args) async {
  final worker = await PipeWorker.openTrustedClient(
    args[2],
    currentUserSid(),
    args[1],
  );
  final mode = args[3];
  final bootstrap = TrustedBootstrapClient(
    pipe: worker,
    generation: generation,
    token: mode == 'wrong-token' ? List.filled(32, 9) : token,
  );
  TrustedApiClient? api;
  try {
    if (const {
      'wrong-token',
      'bad-proof',
      'hello-role',
      'hello-generation',
      'hello-build',
      'hello-version',
      'hello-shape',
      'bootstrap-timeout',
    }.contains(mode)) {
      try {
        await bootstrap.authenticate();
        throw StateError('EXPECTED_BOOTSTRAP_REFUSAL');
      } on StateError catch (e) {
        final expected =
            const {
              'hello-generation',
              'hello-build',
              'hello-version',
            }.contains(mode)
            ? 'INCOMPATIBLE'
            : mode == 'wrong-token'
            ? 'SERVICE_UNAVAILABLE'
            : mode == 'bootstrap-timeout'
            ? 'TIMEOUT'
            : 'UNAUTHORIZED';
        check(e.message == expected);
      }
      stdout.writeln('CLIENT_PASS');
      return;
    }
    final session = await bootstrap.authenticate();
    check(
      session.peer.role == BundlePeerRole.locald &&
          session.role ==
              (mode == 'mcp' || mode.startsWith('grant')
                  ? OperationalRole.mcp
                  : OperationalRole.owner),
    );
    check(session.grant == null);
    await session.revalidate();
    if (mode.startsWith('grant')) {
      if (mode == 'grant-bad-proof') {
        try {
          await session.openGrant(files(args[1]), grantId);
          throw StateError('EXPECTED_GRANT_REFUSAL');
        } on StateError catch (e) {
          check(e.message == 'UNAUTHORIZED' && session.grant == null);
        }
        stdout.writeln('CLIENT_PASS');
        return;
      }
      final result = await session.openGrant(files(args[1]), grantId);
      check(
        identical(session.grant, result) &&
            result.workspaceId == workspace &&
            result.grantId == grantId &&
            result.revision == 4,
      );
      if (mode == 'grant-repeat') {
        try {
          await session.openGrant(files(args[1]), grantId);
          throw StateError('EXPECTED_REPEAT_REFUSAL');
        } on StateError catch (e) {
          check(e.message == 'UNAUTHORIZED');
        }
        stdout.writeln('CLIENT_PASS');
        return;
      }
    }
    if (mode == 'single-use') {
      try {
        await bootstrap.authenticate();
        throw StateError('EXPECTED_SINGLE_USE');
      } on StateError catch (e) {
        check(e.message == 'UNAUTHORIZED');
      }
      try {
        await session.revalidate();
        throw StateError('EXPECTED_RETIRED_SESSION');
      } on StateError catch (e) {
        check(e.message == 'UNAUTHORIZED');
      }
      stdout.writeln('CLIENT_PASS');
      return;
    }
    api = TrustedApiClient(session);
    try {
      TrustedApiClient(session);
      throw StateError('EXPECTED_RPC_OWNER_REFUSAL');
    } on TrustedRpcException catch (e) {
      check(e.code == 'SERVICE_UNAVAILABLE' && !e.terminal);
    }
    if (mode == 'codes') {
      for (final code in TrustedLocalError.codes) {
        await domain(
          api.call('session.ping', {'fixtureCode': code}),
          code,
          terminal: false,
        );
        check(!api.isClosed);
      }
      check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
    } else if (mode == 'quota') {
      check(maxPendingPerSession == 16);
      final requests = [
        for (var n = 0; n < maxPendingPerSession; n++)
          api.call(
            'session.ping',
            {},
            requestId:
                '30000000-0000-4000-8000-${(n + 1).toRadixString(16).padLeft(12, '0')}',
          ),
      ];
      await domain(
        api.call('session.ping', {}),
        'RESOURCE_LIMIT',
        terminal: false,
      );
      await domain(
        api.call(
          'session.ping',
          {},
          requestId: '30000000-0000-4000-8000-000000000001',
        ),
        'IDEMPOTENCY_CONFLICT',
        terminal: false,
      );
      final results = await Future.wait(requests);
      check(
        results.every((r) => r['leaseSeconds'] == 60) &&
            api.pendingRequests == 0,
      );
    } else if (mode == 'connection') {
      for (final method in connectionBadMethods.values) {
        final result = await api.call(method, {
          if (method == 'servers.connectStatus' ||
              method == 'servers.connectCancel')
            'operationId': grantId
          else
            'profileId': workspace,
        });
        check(jsonEncode(result) == jsonEncode(connectionResult(method)));
        try {
          if (method == 'servers.connection') {
            ((result['identity'] as Map)['key'] as Map).clear();
          } else {
            result.clear();
          }
          throw StateError('EXPECTED_FROZEN_RESULT');
        } on UnsupportedError {
          /* Expected actual client immutable capture. */
        }
      }
      check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
    } else if (mode == 'receipts') {
      final result = await api.call('mutations.recent', {});
      check(jsonEncode(result) == jsonEncode(recent()));
      try {
        result.clear();
        throw StateError('EXPECTED_FROZEN_RESULT');
      } on UnsupportedError {
        /* Expected immutable capture. */
      }
      check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
    } else if ({
      ...connectionBadMethods.keys,
      'readiness2',
      'bad-receipt',
      'bad-retry',
      'unknown-code',
      'bad-field',
      'wrong-id',
      'wrong-generation',
      'oversize',
      'invalid-json',
      'timeout',
      'eof',
    }.contains(mode)) {
      final method =
          connectionBadMethods[mode] ??
          (mode == 'readiness2'
              ? 'readiness.get'
              : mode == 'bad-receipt'
              ? 'mutations.recent'
              : 'session.ping');
      await domain(
        api.call(method, {}),
        mode == 'timeout'
            ? 'TIMEOUT'
            : mode == 'eof'
            ? 'SERVICE_UNAVAILABLE'
            : 'UNAUTHORIZED',
        terminal: true,
      );
      await api.done;
      check(api.isClosed && api.pendingRequests == 0);
    } else if (mode == 'duplicate') {
      check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
      await api.done;
      check(api.isClosed);
    } else {
      final readiness = await api.readiness();
      check(
        readiness.toJson()['storageSchema'] == 3 && !readiness.features.any,
      );
      check((await api.call('session.ping', {}))['leaseSeconds'] == 60);
      final text = 'e\u0301 🐧';
      check((await api.call('fixture.echo', {'text': text}))['text'] == text);
    }
    stdout.writeln('CLIENT_PASS');
  } finally {
    if (api != null) await api.close();
    await bootstrap.close();
  }
}

/// Independent protocol fixture, not a format3 locald registry/service. Uses
/// actual TrustedPipePeer and canonical HMAC transcript, no injected callbacks.
Future<void> server(List<String> args) async {
  final root = args[1], mode = args[3], name = args[2];
  final worker = await PipeWorker.createTrustedServer(
    name,
    currentUserSid(),
    root,
  );
  Process? child;
  final childOut = StringBuffer(), childErr = StringBuffer();
  Future<void>? outDone, errDone;
  try {
    if (mode.startsWith('grant')) {
      final private = p.join(root, 'private');
      createProtectedDirectory(root, private, currentUserSid());
      var folder = private;
      for (final component in [
        'ServerDeckNext',
        'v1',
        'workspaces',
        'default',
      ]) {
        folder = p.join(folder, component);
        createProtectedDirectory(root, folder, currentUserSid());
      }
      final binding = McpCredentialBinding(
        workspaceId: workspace,
        grantId: grantId,
        secretRef: '10000000-0000-4000-8000-000000000004',
        ownerSid: currentUserSid(),
        issuedAt: '2026-10-22T00:00:00.000Z',
      );
      await files(root).stage(binding);
      await files(root).publish(binding, revoked: false);
    }
    final accepted = worker.accept(deadline: const Duration(seconds: 5));
    accepted.ignore();
    child = await Process.start(
      p.join(
        root,
        mode == 'mcp' || mode.startsWith('grant')
            ? 'mcp.exe'
            : 'serverdeck.exe',
      ),
      ['client', root, name, mode],
    );
    Future<void> capture(Stream<List<int>> stream, StringBuffer target) async {
      var bytes = 0;
      await for (final chunk in stream) {
        bytes += chunk.length;
        check(bytes <= 16384);
        target.write(utf8.decode(chunk, allowMalformed: true));
      }
    }

    outDone = capture(child.stdout, childOut);
    errDone = capture(child.stderr, childErr);
    await accepted;
    final peer = await worker.verifyTrustedPeer();
    final io = TrustedHandshakeIo(peer);
    Duration remaining() => const Duration(seconds: 6);
    final role = peer.role == BundlePeerRole.owner
        ? OperationalRole.owner
        : OperationalRole.mcp;
    if (mode == 'bootstrap-timeout') {
      await child.exitCode.timeout(const Duration(seconds: 9));
    } else {
      final hello = OperationalHello(
        generation: mode == 'hello-generation' ? workspace : generation,
        serverNonce: nonce(1),
        buildId: mode == 'hello-build'
            ? '${'c' * 40}+Debug+${'b' * 64}'
            : peer.buildId,
        clientRole: mode == 'hello-role'
            ? (role == OperationalRole.owner
                  ? OperationalRole.mcp
                  : OperationalRole.owner)
            : role,
      );
      final document = hello.toJson();
      if (mode == 'hello-version') (document['hello'] as Map)['apiMinor'] = 0;
      if (mode == 'hello-shape') (document['hello'] as Map)['extra'] = 1;
      await io.write(document, remaining);
      if (mode.startsWith('hello-')) {
        await child.exitCode.timeout(const Duration(seconds: 9));
      } else {
        final auth = OperationalAuthenticate.decode(await io.read(remaining));
        final transcript = OperationalBootstrapTranscript(
          hello: hello,
          clientNonce: auth.clientNonce,
          requestedCapabilities: auth.requestedCapabilities,
        );
        check(auth.clientBuildId == peer.buildId);
        final valid = auth.proof == mac(transcript.clientBytes());
        if (mode == 'wrong-token') {
          check(!valid);
          await worker.close();
        } else {
          check(valid);
          final unsigned = OperationalAuthenticated(
            sessionId: nonce(2),
            clientRole: role,
            capabilities: [role.name],
            proof: nonce(3),
          );
          final reply = OperationalAuthenticated(
            sessionId: unsigned.sessionId,
            clientRole: role,
            capabilities: unsigned.capabilities,
            proof: mode == 'bad-proof'
                ? nonce(9)
                : mac(transcript.serverBytes(unsigned)),
          );
          await io.write(reply.toJson(), remaining);
          if (mode == 'bad-proof' || mode == 'single-use') {
            await child.exitCode.timeout(const Duration(seconds: 9));
          } else {
            Future<Map<String, Object?>> read() async {
              Future<Uint8List> fill(int n) async {
                final data = <int>[];
                while (data.length < n) {
                  final bytes = await peer.read(
                    count: (n - data.length).clamp(1, 65536),
                    deadline: const Duration(seconds: 8),
                  );
                  check(bytes.isNotEmpty);
                  data.addAll(bytes);
                }
                return Uint8List.fromList(data);
              }

              final size = ByteData.sublistView(await fill(4))
                  .getUint32(0, Endian.little);
              check(size > 0 && size <= maxRequestBytes);
              final value = StrictCodec().decode(await fill(size));
              check(value['sessionId'] == reply.sessionId);
              return value;
            }

            Future<void> write(Map<String, Object?> value) => peer.write(
              frameBytes(encodeMcpMessage(value), maxBytes: maxResponseBytes),
            );
            Map<String, Object?> response(
              Map<String, Object?> request, {
              Map<String, Object?>? result,
              Map<String, Object?>? error,
            }) => {
              'v': 1,
              'id': request['id'],
              'generation': generation,
              if (error != null)
                'error': error
              else
                'result': result ?? {'leaseSeconds': 60},
            };
            if (mode.startsWith('grant')) {
              final opening = await read();
              check(opening['method'] == 'mcp.open');
              final params = McpOpenRequest.fromJson(opening['params']);
              final loaded = await files(root).readForBridge(grantId);
              try {
                final context = McpOpenTranscript(
                  hello: hello,
                  workspaceId: workspace,
                  sessionId: reply.sessionId,
                  clientNonce: params.clientNonce,
                  grantId: grantId,
                  secretRef: loaded.binding.secretRef,
                );
                final clientBytes = context.clientBytes();
                try {
                  check(
                    await loaded.key.verify(
                      clientBytes,
                      base64Url.decode('${params.proof}='),
                    ),
                  );
                } finally {
                  clientBytes.fillRange(0, clientBytes.length, 0);
                }
                final expiry = DateTime.fromMillisecondsSinceEpoch(
                  DateTime.now().millisecondsSinceEpoch,
                  isUtc: true,
                ).add(const Duration(minutes: 5)).toIso8601String();
                final unsigned = McpOpenResult(
                  workspaceId: workspace,
                  grantId: grantId,
                  revision: 4,
                  expiresAt: expiry,
                  proof: nonce(3),
                );
                final serverBytes = context.serverBytes(unsigned);
                late final List<int> proof;
                try {
                  proof = await loaded.key.mac(serverBytes);
                } finally {
                  serverBytes.fillRange(0, serverBytes.length, 0);
                }
                final result = McpOpenResult(
                  workspaceId: workspace,
                  grantId: grantId,
                  revision: 4,
                  expiresAt: expiry,
                  proof: mode == 'grant-bad-proof'
                      ? nonce(9)
                      : base64Url.encode(proof).replaceAll('=', ''),
                );
                await write(response(opening, result: result.toJson()));
              } finally {
                loaded.key.close();
              }
              if (mode == 'grant') {
                await write(
                  response(
                    await read(),
                    result: TrustedReadiness(
                      state: ReadinessState.ready,
                      generation: generation,
                      workspaceId: workspace,
                    ).toJson(),
                  ),
                );
                await write(response(await read()));
                final echo = await read();
                await write(
                  response(
                    echo,
                    result: Map<String, Object?>.from(echo['params'] as Map),
                  ),
                );
              }
            } else if (mode == 'quota') {
              final requests = [
                for (var n = 0; n < maxPendingPerSession; n++) await read(),
              ];
              for (final request in requests.reversed) {
                await write(response(request));
              }
            } else if (mode == 'codes') {
              for (final code in TrustedLocalError.codes) {
                final request = await read();
                check((request['params'] as Map)['fixtureCode'] == code);
                await write(
                  response(request, error: TrustedLocalError(code).toJson()),
                );
              }
              await write(response(await read()));
            } else if (mode == 'connection') {
              for (final method in connectionBadMethods.values) {
                final request = await read();
                check(request['method'] == method);
                await write(
                  response(request, result: connectionResult(method)),
                );
              }
              await write(response(await read()));
            } else if (connectionBadMethods.containsKey(mode)) {
              final request = await read();
              final method = connectionBadMethods[mode]!;
              check(request['method'] == method);
              final result = connectionResult(method);
              if (mode == 'bad-connection') {
                result['identity'] = null;
              } else {
                result['unexpected'] = true;
              }
              await write(response(request, result: result));
            } else if (mode == 'receipts') {
              await write(response(await read(), result: recent()));
              await write(response(await read()));
            } else if (mode == 'readiness2') {
              await write(
                response(
                  await read(),
                  result: OperationalReadiness(
                    state: ReadinessState.ready,
                    generation: generation,
                    workspaceId: workspace,
                  ).toJson(),
                ),
              );
            } else if (mode == 'bad-receipt') {
              final value = recent();
              ((value['receipts'] as List).first as Map)['operation'] =
                  'servers.trust.delete';
              await write(response(await read(), result: value));
            } else if (mode == 'timeout') {
              await read();
              await child.exitCode.timeout(const Duration(seconds: 9));
            } else if (mode == 'eof') {
              await read();
              await worker.close();
            } else if (mode == 'oversize') {
              await read();
              final header = ByteData(4)
                ..setUint32(0, maxResponseBytes + 1, Endian.little);
              await peer.write(header.buffer.asUint8List());
            } else if (mode == 'invalid-json') {
              await read();
              await peer.write(frameBytes(utf8.encode('{bad}')));
            } else if (mode == 'bad-retry' ||
                mode == 'unknown-code' ||
                mode == 'bad-field') {
              final error = TrustedLocalError('TRUST_REQUIRED').toJson();
              if (mode == 'bad-retry') error['retry'] = 'reconnect';
              if (mode == 'unknown-code') error['code'] = 'FUTURE_CODE';
              if (mode == 'bad-field') error['field'] = 'address';
              await write(response(await read(), error: error));
            } else if (mode == 'wrong-id' || mode == 'wrong-generation') {
              final value = response(await read());
              value[mode == 'wrong-id' ? 'id' : 'generation'] = workspace;
              await write(value);
            } else if (mode == 'duplicate') {
              final value = response(await read());
              await write(value);
              await write(value);
            } else {
              await write(
                response(
                  await read(),
                  result: TrustedReadiness(
                    state: ReadinessState.ready,
                    generation: generation,
                    workspaceId: workspace,
                  ).toJson(),
                ),
              );
              await write(response(await read()));
              final request = await read();
              await write(
                response(
                  request,
                  result: Map<String, Object?>.from(request['params'] as Map),
                ),
              );
            }
          }
        }
      }
    }
    final childExit = await child.exitCode.timeout(const Duration(seconds: 12));
    await outDone;
    await errDone;
    if (childExit != 0 ||
        !childOut.toString().contains('CLIENT_PASS') ||
        childErr.isNotEmpty) {
      stderr.write(childErr.toString());
      throw StateError('TRUSTED_CLIENT_CHILD_FAILED');
    }
  } finally {
    if (child != null) {
      try {
        await child.stdin.close();
      } on IOException {
        /* Owned child exited. */
      }
      child.kill();
      await child.exitCode.timeout(const Duration(seconds: 5));
    }
    await worker.close();
  }
}

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args[3].startsWith('cleanup')) {
      await cleanup.run(args, generation, token);
      if (args[0] == 'server') stdout.writeln('PASS:${args[3]}');
      return;
    }
    if (args[0] == 'client') {
      await client(args);
    } else {
      await server(args);
      stdout.writeln('PASS:${args[3]}');
    }
  } catch (error, stack) {
    stderr.writeln(error);
    stderr.writeln(stack);
    exitCode = 1;
  }
}
