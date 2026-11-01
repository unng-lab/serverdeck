import 'package:serverdeck_engine/platform/ports.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:serverdeck_engine/hosting/authority.dart';
import 'package:serverdeck_engine/hosting/control_services.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/mcp/grants.dart';
import 'package:serverdeck_engine/api/owner_api.dart';
import 'package:serverdeck_engine/platform/verified_release.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:test/test.dart';

import '../hosting/control_services_lifecycle_test.dart' as platform;
import '../hosting/sessions_test.dart' show Channel, nonce;
import '../remote/read_clock_test.dart' show sections;
import '../remote/ssh_io_policy_test.dart' as bytes;
import '../storage/actual_state_store_test.dart' as actual;
import 'schema3_fixture.dart' as fixture;

const allToolNames = {
  'servers_list',
  'server_get',
  'server_connect',
  'server_disconnect',
  'state_get',
  'configuration_get',
  'logs_read',
  'profiles_list',
  'profiles_get',
  'profiles_create',
  'profiles_update',
  'profiles_compare',
  'profiles_validate',
  'profiles_archive',
  'recipes_list',
  'plan_create',
  'plans_get',
  'approval_request',
  'apply',
  'jobs_list',
  'jobs_get',
  'jobs_events',
  'jobs_cancel',
  'jobs_reconcile',
};
String fullName(String short) => 'serverdeck_$short';
DateTime utcNow() => DateTime.fromMillisecondsSinceEpoch(
  DateTime.now().millisecondsSinceEpoch,
  isUtc: true,
);

final class Client {
  Client(this.channel, this.authenticated, this.grantId, this.peer);
  final String channel, grantId;
  final OperationalAuthenticated authenticated;
  final Channel peer;
}

/// Actual production service composition and real store/authentication. Only
/// platform proofs, protected files and SSH byte transport are RAM providers.
final class Setup {
  Setup(
    this.repository,
    this.store, {
    String? generation,
    VerifiedAppConfiguration? bundle,
  }) : runtime = generation == null
           ? platform.Runtime(root: bundle?.appRoot ?? '/ram/app')
           : platform.Runtime(
               generation: generation,
               root: bundle?.appRoot ?? '/ram/app',
             );
  final actual.Setup repository;
  final StateStore store;
  final platform.Runtime runtime;
  final io = bytes.Io();
  late HostAuthority host;
  late EngineSessions sessions;
  late TrustedControlServices services;
  int _counter = 1000;
  final successful = <String>{};
  bool _closed = false;
  OwnerSession? _owner;

  static Future<Setup> create({
    bool populated = true,
    VerifiedAppConfiguration? bundle,
    EngineClock? readClock,
    VerifiedExecutorRelease? executorRelease,
    void Function(bytes.Session)? executor,
  }) async {
    final data = await actual.Setup.create(populated: populated);
    return reopen(
      data,
      bundle: bundle,
      executorRelease: executorRelease,
      executor: executor,
      readClock: readClock,
      requestCounterStart: 1000,
    );
  }

  /// New actual host/session generation over the same positively closed RAM
  /// repository. Loader, custody, recovery and service creation are unchanged.
  static Future<Setup> reopen(
    actual.Setup data, {
    VerifiedAppConfiguration? bundle,
    EngineClock? readClock,
    VerifiedExecutorRelease? executorRelease,
    void Function(bytes.Session)? executor,
    String? generation,
    int requestCounterStart = 2000,
  }) async {
    final s = Setup(
      data,
      await data.open(),
      generation: generation,
      bundle: bundle,
    );
    s._counter = requestCounterStart;
    s.host = HostAuthority.prepare(
      runtime: s.runtime,
      lease: data.source.lease,
      generation: s.runtime.gate.generation,
    );
    await s.host.initialize();
    s.sessions = EngineSessions.withAuthority(
      authority: s.host,
      admissionBlocked: () => false,
    );
    s.io.observed = s.store.snapshot.foundation.trust[fixture.profile]?.key;
    s.io.onStart = () {
      s.io.attempts.last.client.onExecute = (session, command) {
        final read = command.read;
        if (read == null) {
          if (executor == null)
            throw StateError('UNDECLARED_EXECUTOR_BYTE_INPUT');
          executor(session);
        } else {
          s.respond(session, read.source);
        }
      };
    };
    s.services = await TrustedControlServices.create(
      store: s.store,
      custody: data.source.custody,
      receiptKey: data.source.key,
      sessions: s.sessions,
      bundle: bundle,
      sshIo: s.io,
      executorRelease: executorRelease,
      readClock: readClock,
    );
    addTearDown(s.close);
    return s;
  }

  Future<Map<String, Object?>> ownerCall(
    String method,
    Map<String, Object?> args,
  ) async {
    final owner = _owner ??= await sessions.openOwner(
      await host.bindOwner(Object()),
    );
    final request = owner.reserve(method);
    TrustedOwnerInvocation? invocation;
    try {
      invocation = services.prepare(
        request,
        method,
        args,
        requestId: actual.id(_counter++),
      );
      await owner.admit(request);
      return await invocation.execute();
    } finally {
      invocation?.close();
      request.complete();
      await request.settled;
    }
  }

  Future<Map<String, Object?>> ownerRead(
    String method,
    Map<String, Object?> args,
  ) async {
    var result = await ownerCall(method, args);
    for (var i = 0; result['state'] == 'running' && i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
      result = await ownerCall('servers.readStatus', {
        'operationId': result['operationId'],
      });
    }
    expect(result['state'], 'succeeded', reason: 'actual owner read $method');
    return Map<String, Object?>.from(result['result'] as Map);
  }

  Future<String> grant({
    List<String> scopes = const ['read', 'logs', 'author', 'plan', 'apply'],
    List<String>? targets,
    DateTime Function()? clock,
    int lifetimeSeconds = 300,
  }) async {
    final id = actual.id(_counter++), request = actual.id(_counter++);
    await store.mutateOwnerGrant(
      OwnerGrantCommand.parse('grant.create', {
        'requestId': request,
        'grantId': id,
        'label': 'actual MCP unit',
        'scopes': scopes,
        'serverIds':
            targets ??
            (scopes.any((s) => s != 'author') ? [fixture.profile] : <String>[]),
        'lifetimeSeconds': lifetimeSeconds,
      }),
      clock: clock ?? utcNow,
    );
    return id;
  }

  Future<Client> client(String grantId) async {
    final channel = 'actual-ram-mcp-${_counter++}';
    final peer = Channel(
      runtime.ownerIdentity,
      runtime.appRoot,
      runtime.buildId,
    );
    final handshake = McpServerHandshake(
      peer: peer,
      token: List.filled(32, 7),
      channel: channel,
      sessions: sessions,
    );
    final hello = await handshake.hello();
    final bootstrap = OperationalBootstrapTranscript(
      hello: hello,
      clientNonce: nonce(9),
      requestedCapabilities: ['mcp'],
    );
    final secret = SecretKeyData(
      List.filled(32, 7),
      overwriteWhenDestroyed: true,
    );
    late String proof;
    try {
      proof = base64Url
          .encode(
            DartHmac.sha256()
                .calculateMacSync(
                  bootstrap.clientBytes(),
                  secretKeyData: secret,
                  nonce: [],
                )
                .bytes,
          )
          .replaceAll('=', '');
    } finally {
      secret.destroy();
    }
    final authenticated = await handshake.authenticate(
      StrictCodec().encode(
        OperationalAuthenticate(
          clientNonce: nonce(9),
          clientBuildId: hello.buildId,
          requestedCapabilities: ['mcp'],
          proof: proof,
        ).toJson(),
        maxBytes: 4096,
      ),
    );
    // Obtain the actual protected key. For an expired grant, constructing its
    // valid proof is still possible from retained artifacts; authority must deny.
    final grant = store.snapshot.automation.grants[grantId]!;
    final binding = McpCredentialBinding(
      workspaceId: fixture.workspace,
      grantId: grantId,
      secretRef: grant.secretRef,
      ownerSid: fixture.owner,
      issuedAt: grant.issuedAt.toIso8601String(),
    );
    final key = await repository.source.artifacts.openReferenced(binding);
    final request = await sessions.begin(
      channel,
      authenticated.sessionId,
      'mcp.open',
    );
    try {
      final transcript = McpOpenTranscript(
        hello: hello,
        workspaceId: fixture.workspace,
        sessionId: authenticated.sessionId,
        clientNonce: nonce(11),
        grantId: grantId,
        secretRef: grant.secretRef,
      );
      final opened = await request.openGrant(
        services.authority,
        McpOpenRequest(
          grantId: grantId,
          clientNonce: nonce(11),
          proof: base64Url
              .encode(await key.mac(transcript.clientBytes()))
              .replaceAll('=', ''),
        ).toJson(),
      );
      expect(
        await key.verify(
          transcript.serverBytes(opened),
          base64Url.decode('${opened.proof}='),
        ),
        isTrue,
      );
    } finally {
      key.close();
      request.complete();
      await request.settled;
    }
    return Client(channel, authenticated, grantId, peer);
  }

  Future<Map<String, Object?>> invoke(
    Client client,
    Map<String, Object?> input,
  ) async {
    final request = await sessions.begin(
      client.channel,
      client.authenticated.sessionId,
      'mcp.invoke',
    );
    try {
      return (await services.router.invoke(request, input)).toJson();
    } finally {
      request.complete();
      await request.settled;
    }
  }

  Future<Map<String, Object?>> tool(
    Client client,
    String name,
    Map<String, Object?> arguments,
  ) async {
    var reply = await invoke(client, {
      'request': {'name': fullName(name), 'arguments': arguments},
    });
    for (var i = 0; reply['done'] == false && i < 100; i++) {
      await Future<void>.delayed(Duration.zero);
      reply = await invoke(client, {
        'poll': {'operationId': reply['operationId']},
      });
    }
    expect(
      reply['done'],
      isTrue,
      reason: 'bounded client poll must settle $name',
    );
    final result = reply['result'];
    if (result is Map && (result['structuredContent'] as Map)['ok'] == true)
      successful.add(name);
    return reply;
  }

  void respond(bytes.Session session, SshReadSource source) {
    final observed = utcNow().toIso8601String();
    final text = switch (source) {
      SshReadSource.system => sections({
        'osRelease': 'ID=ubuntu\nVERSION_ID="24.04"\nPRETTY_NAME="unit Ubuntu"',
        'kernel': 'unit',
        'architecture': 'x86_64',
        'hostname': 'unit',
        'uptime': '3600 1800',
        'bootId': 'unit-boot',
        'observedAt': observed,
      }),
      SshReadSource.metrics => sections({
        'cpu': 'cpu 100 0 10 100 0 0 0 0',
        'memory': 'MemTotal: 1000 kB\nMemAvailable: 500 kB',
        'disk': 'Filesystem 1K-blocks Used Available Use% Mounted on\nunit 1000 500 500 50% /',
        'network': 'lo: 100 0 0 0 0 0 0 0 200 0 0 0 0 0 0 0',
        'observedAt': observed,
      }),
      SshReadSource.packages => 'unit-package\t1.0\tii \n',
      SshReadSource.units => 'unit.service loaded active running unit\n',
      SshReadSource.journal =>
        jsonEncode({
              '__CURSOR': 'unit-1',
              '__REALTIME_TIMESTAMP': '${utcNow().microsecondsSinceEpoch}',
              '_SYSTEMD_UNIT': 'unit.service',
              'PRIORITY': '6',
              'MESSAGE': 'unit log',
            }) +
            '\n',
    };
    session.output.add(Uint8List.fromList(utf8.encode(text)));
    session.finish().ignore();
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await services.close();
    await sessions.close();
    await host.close();
    await store.close();
    expect(repository.source.lease.closes, 0);
  }
}

Map<String, Object?> success(Map<String, Object?> reply) {
  final result = Map<String, Object?>.from(reply['result'] as Map);
  expect(result['isError'], isFalse);
  final structured = result['structuredContent'] as Map;
  expect(structured['ok'], isTrue);
  return Map<String, Object?>.from(structured['data'] as Map);
}
