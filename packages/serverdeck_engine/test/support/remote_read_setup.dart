import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:serverdeck_engine/api/owner_api.dart';
import 'package:serverdeck_engine/api/owner_connections.dart';
import 'package:serverdeck_engine/api/owner_reads.dart';
import 'package:serverdeck_engine/hosting/authority.dart';
import 'package:serverdeck_engine/hosting/sessions.dart';
import 'package:serverdeck_engine/mcp/connection_services.dart';
import 'package:serverdeck_engine/mcp/read_services.dart';
import 'package:serverdeck_engine/mcp/router.dart';
import 'package:serverdeck_engine/remote/connections.dart';
import 'package:serverdeck_engine/remote/reads.dart';
import 'package:serverdeck_engine/remote/ssh_transport.dart';
import 'package:serverdeck_engine/storage/state_store.dart';
import 'package:serverdeck_engine/storage/key_custody.dart';
import 'package:serverdeck_engine/storage/executor_enrollments.dart';
import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:test/test.dart';

import '../hosting/control_services_lifecycle_test.dart' as host;
import '../hosting/sessions_test.dart' show Channel, nonce;
import '../hosting/target_changes_test.dart' as publication;
import '../remote/read_clock_test.dart' show Clock, sections, observed;
import '../remote/ssh_io_policy_test.dart' as bytes;
import '../remote/ssh_pool_lifecycle_test.dart' show settle;
import '../storage/mcp_grant_handle_test.dart' as grantFixture;
import '../storage/workspace_snapshot_test.dart' as snapshotFixture;
import 'schema3_fixture.dart' as fixture;
import 'remote_read_graph.dart';

/// Repository boundary with real validated schema3 and real credential custody.
/// Only declared read/publication operations exist; unexpected effects fail.
final class Store implements StateStore {
  Store(this.grants) : value = grants.value;
  final grantFixture.Store grants;
  WorkspaceSnapshot value;
  int enrollmentReads = 0;
  Completer<void>? enrollmentRead;
  bool metadataBlocked = false;
  Future<void> _enrollmentTail = Future<void>.value();
  late final enrollments = ExecutorEnrollmentStore(
    files: grants.data.files,
    lease: grants.data.lease,
    custody: grants.data.custody,
    key: grants.data.key,
    requireReady: () {
      snapshot;
    },
    onStorageBlocked: () => metadataBlocked = true,
  );
  final listeners = <void Function(String, int)>{};
  @override
  bool get isReady => true;
  @override
  WorkspaceSnapshot get snapshot => value;
  @override
  void assertAutomationCustody(KeyCustody actual, ReceiptKeyMaterial receipt) {
    expect(identical(actual, grants.data.custody), isTrue);
    expect(identical(receipt, grants.data.key), isTrue);
  }

  @override
  Future<Map<String, ExecutorEnrollment>> readExecutorEnrollments() {
    enrollmentReads++;
    final actual = _enrollmentTail.then((_) async {
      await enrollmentRead?.future;
      return enrollments.read();
    });
    _enrollmentTail = actual.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return actual;
  }

  @override
  ClientGrantRecord currentMcpGrant(String id, {required DateTime at}) =>
      grants.currentMcpGrant(id, at: at);
  @override
  Future<McpGrantKey> openMcpGrantKey(
    String id, {
    required DateTime Function() clock,
    Duration? publicationDeadline,
  }) => grants.openMcpGrantKey(
    id,
    clock: clock,
    publicationDeadline: publicationDeadline,
  );
  @override
  void Function() onMcpGrantPublished(void Function(String, int) listener) {
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void revoke() {
    grants.current = ClientGrantRecord.fromJson({
      ...grants.current.toJson(),
      'revision': 2,
      'revokedAt': fixture.second,
    });
    for (final listener in listeners.toList()) listener(fixture.grant, 2);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('NO_UNDECLARED_REPOSITORY_EFFECT_IN_UNIT');
}

final class Mcp {
  Mcp(this.channel, this.authenticated, this.context);
  final String channel;
  final OperationalAuthenticated authenticated;
  final TrustedMcpContext context;
}

/// Actual domain composition over RAM files/vault/proofs and byte I/O only.
final class Setup {
  Setup(this.data, this.store, {String generation = publication.profile})
    : runtime = host.Runtime(generation: generation);
  final snapshotFixture.Setup data;
  final Store store;
  final host.Runtime runtime;
  final io = bytes.Io(), clock = Clock();
  late HostAuthority hostAuthority;
  late EngineSessions sessions;
  late TrustedMcpAuthority authority;
  late SshTransportPool pool;
  late TrustedConnectionService connections;
  late RemoteReadService reads;
  late RemoteReadOwnerApi ownerReads;
  late TrustedOwnerApiGroup ownerApi;
  late TrustedMcpRouter router;
  late OwnerSession owner;
  final held = <bytes.Session>[];
  final owners = <OwnerSession>[];
  bool holdSystem = false;
  bool Function(bytes.Session, SshReadSource)? response;

  static Future<Setup> create({
    int profiles = 1,
    bool wide = false,
    List<String> scopes = const ['read'],
    String generation = publication.profile,
  }) async {
    final data = await snapshotFixture.Setup.create(populated: true);
    if (profiles != 1 ||
        wide ||
        scopes.length != 1 ||
        scopes.single != 'read') {
      await expandReadGraph(
        data,
        profiles: profiles,
        wide: wide,
        scopes: scopes,
      );
    }
    final s = Setup(
      data,
      Store(grantFixture.Store(data, await data.load())),
      generation: generation,
    );
    s.hostAuthority = HostAuthority.prepare(
      runtime: s.runtime,
      lease: data.lease,
      generation: generation,
    );
    await s.hostAuthority.initialize();
    s.sessions = EngineSessions.withAuthority(
      authority: s.hostAuthority,
      admissionBlocked: () => false,
    );
    // Authority time is independent from the cache clock and always validates
    // the fixture's real current metadata; no parsed role/context is injected.
    s.authority = TrustedMcpAuthority(
      s.store,
      clock: () => DateTime.parse(fixture.second),
    );
    s.io.observed = s.store.snapshot.foundation.trust[fixture.profile]!.key;
    s.io.onStart = () {
      s.io.attempts.last.client.onExecute = (session, command) {
        if (s.holdSystem && command.read!.source == SshReadSource.system) {
          session.autoClose = false;
          s.held.add(session);
        } else {
          s.respond(session, command.read!.source);
        }
      };
    };
    s.pool = SshTransportPool(io: s.io);
    s.connections = TrustedConnectionService(
      store: s.store,
      custody: data.custody,
      sessions: s.sessions,
      authority: s.authority,
      transports: s.pool,
    );
    s.reads = RemoteReadService(s.connections, clock: s.clock);
    s.ownerReads = RemoteReadOwnerApi(s.reads);
    s.ownerApi = TrustedOwnerApiGroup([
      ConnectionOwnerApi(s.connections),
      s.ownerReads,
    ]);
    s.router = TrustedMcpRouter(
      sessions: s.sessions,
      authority: s.authority,
      services: RemoteReadMcpServices(s.reads),
    );
    s.owner = await s.newOwner();
    await s.ownerCall('servers.connect', {'profileId': fixture.profile});
    await settle();
    expect(
      (await s.ownerCall('servers.connectStatus', {
        'operationId': fixture.request1,
      }))['state'],
      'succeeded',
    );
    addTearDown(s.close);
    return s;
  }

  void respond(bytes.Session session, SshReadSource source) {
    if (response?.call(session, source) ?? false) return;
    final text = switch (source) {
      SshReadSource.system => sections({
        'osRelease': 'ID=debian\nVERSION_ID=12\nPRETTY_NAME="unit"',
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
      SshReadSource.journal => '',
    };
    session.output.add(Uint8List.fromList(utf8.encode(text)));
    session.finish().ignore();
  }

  Future<OwnerSession> newOwner() async {
    final owner = await sessions.openOwner(
      await hostAuthority.bindOwner(Object()),
    );
    owners.add(owner);
    return owner;
  }

  Future<Map<String, Object?>> ownerCall(
    String method,
    Map<String, Object?> args, {
    OwnerSession? asOwner,
    String id = fixture.request1,
  }) async {
    final actual = asOwner ?? owner, request = actual.reserve(method);
    TrustedOwnerInvocation? invocation;
    try {
      invocation = ownerApi.prepare(request, method, args, requestId: id);
      await actual.admit(request);
      return await invocation.execute();
    } finally {
      invocation?.close();
      request.complete();
    }
  }

  Future<TrustedOwnerReadContext> ownerContext([OwnerSession? asOwner]) async {
    final actual = asOwner ?? owner, request = actual.reserve('servers.state');
    try {
      await actual.admit(request);
      return request.ownerReadContext();
    } finally {
      request.complete();
    }
  }

  Future<Mcp> mcp([String channel = 'ram-mcp']) async {
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
    final key = await data.artifacts.openReferenced(data.binding);
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
        grantId: fixture.grant,
        secretRef: fixture.secretRef,
      );
      final reply = await request.openGrant(
        authority,
        McpOpenRequest(
          grantId: fixture.grant,
          clientNonce: nonce(11),
          proof: base64Url
              .encode(await key.mac(transcript.clientBytes()))
              .replaceAll('=', ''),
        ).toJson(),
      );
      expect(
        await key.verify(
          transcript.serverBytes(reply),
          base64Url.decode('${reply.proof}='),
        ),
        isTrue,
      );
    } finally {
      key.close();
      request.complete();
      await request.settled;
    }
    final invocation = await sessions.begin(
      channel,
      authenticated.sessionId,
      'mcp.invoke',
    );
    try {
      return Mcp(channel, authenticated, invocation.mcpContext());
    } finally {
      invocation.complete();
    }
  }

  Future<Map<String, Object?>> invoke(
    Mcp client,
    Map<String, Object?> input,
  ) async {
    final request = await sessions.begin(
      client.channel,
      client.authenticated.sessionId,
      'mcp.invoke',
    );
    try {
      return (await router.invoke(request, input)).toJson();
    } finally {
      request.complete();
      await request.settled;
    }
  }

  Future<void> attach(Mcp client) async {
    final op = ConnectionMcpServices(connections).start(
      client.context,
      mcpTool('serverdeck_server_connect')!,
      {'serverId': fixture.profile},
    );
    expect((await op.result).toJson()['isError'], isFalse);
    await op.cancelInterest();
    expect(io.attempts, hasLength(1));
  }

  Future<void> close() async {
    if (store.enrollmentRead case final actual? when !actual.isCompleted)
      actual.complete();
    holdSystem = false;
    if (runtime.proof case final pause? when !pause.isCompleted)
      pause.complete();
    for (final session in held) {
      if (!session.finishing) await session.finish();
    }
    router.close();
    await ownerReads.close();
    await reads.close();
    await connections.close();
    await authority.closeAndDrain();
    for (final owner in owners) owner.close();
    await sessions.close();
    await pool.close();
    await hostAuthority.close();
    expect(store.listeners, isEmpty);
    expect(store.grants.opened.every((key) => key.closes == 1), isTrue);
    expect(pool.activeTransports, 0);
    expect(data.lease.closes, 0);
  }
}
