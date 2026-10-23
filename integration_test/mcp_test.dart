import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:serverdeck/main.dart' as app;
import 'package:serverdeck_protocol/models.dart';
import 'package:serverdeck_windows/dpapi.dart';

import '../lib/automation/automation_controller.dart';
import '../lib/bootstrap/local_api_client.dart';
import '../lib/profiles/profile_controller.dart';
import '../lib/profiles/profile_list.dart';
import '../lib/servers/server_controller.dart';
import 'support/mcp_actor.dart';
import 'support/runtime_hooks.dart';

// Actual native owner + two independent stdio clients + owned Docker executor.
// This core scenario does not stand in for the separate recipe/crash matrix.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final fixture = _Fixture.open();
  testWidgetsWithRuntimeHooks('actual owner and independent MCP clients', (
    tester,
  ) async {
    _Scenario? scenario;
    try {
      app.main();
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 45)) {
        await tester.pump(const Duration(milliseconds: 100));
        final found = find.byType(ProfileList);
        if (found.evaluate().isEmpty) continue;
        final model = tester.widget<ProfileList>(found.first).controller;
        if (model.loaded &&
            model.bootstrap.state == ReadinessState.ready &&
            model.bootstrap.client.trustedClient != null) {
          scenario = _Scenario(fixture, model);
          break;
        }
      }
      _check(scenario != null, 'OWNER_READY');
      await tester.runAsync(() => scenario!.run());
    } on Object {
      // No assertion renderer may print credentials or received documents.
      fixture.publish('failed.json', {'format': 1, 'code': 'MCP_CORE_FAILED'});
      throw StateError('MCP_CORE_FAILED');
    } finally {
      await tester.runAsync(() async => await scenario?.close());
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

void _check(bool condition, String code) {
  if (!condition) throw StateError('MCP_CASE_$code');
}

Map<String, Object?> _object(Object? value) {
  _check(value is Map<String, Object?>, 'OBJECT');
  return value as Map<String, Object?>;
}

final class _Fixture {
  _Fixture(this.root, this.identity);
  final Directory root;
  final Map<String, Object?> identity;
  String get id => identity['fixtureId'] as String;
  String get repository => root.parent.parent.path;
  String get python => '${root.path}/client-python/Scripts/python.exe';

  static _Fixture open() {
    final profile = Directory(Platform.environment['LOCALAPPDATA'] ?? '');
    _check(Platform.isWindows && profile.isAbsolute, 'OWNED_FIXTURE');
    final root = profile.parent;
    _check(
      RegExp(r'[\\/]\.local[\\/]mcp-acceptance-[a-f0-9]{32}$')
              .hasMatch(root.path) &&
          profile.path.replaceAll('\\', '/').endsWith('/profile') &&
          File(Platform.resolvedExecutable).parent.path
                  .replaceAll('\\', '/')
                  .toLowerCase() ==
              Directory('${root.path}/application bundle').path
                  .replaceAll('\\', '/')
                  .toLowerCase(),
      'OWNED_FIXTURE',
    );
    // The parent creates and verifies the protected owner DACL before launch.
    // Also refuse redirection at the entry itself and every existing ancestor.
    var part = root;
    while (true) {
      _check(!FileSystemEntity.isLinkSync(part.path), 'FIXTURE_LINK');
      final parent = part.parent;
      if (parent.path == part.path) break;
      part = parent;
    }
    final identity = _read('${root.path}/fixture.json');
    _check(
      identity['format'] == 1 &&
          root.path.endsWith('mcp-acceptance-${identity['fixtureId']}') &&
          identity['sourceSnapshotSha256'] is String &&
          RegExp(r'^[a-f0-9]{64}$')
              .hasMatch(identity['sourceSnapshotSha256'] as String),
      'FIXTURE_ID',
    );
    return _Fixture(root, identity);
  }

  static Map<String, Object?> _read(String path) {
    final file = File(path);
    _check(
      !FileSystemEntity.isLinkSync(path) && file.lengthSync() <= 16384,
      'FIXTURE_DOCUMENT',
    );
    return _object(jsonDecode(file.readAsStringSync()));
  }

  Future<Map<String, Object?>> waitDocument(String name) async {
    _check(name == 'enrolled.json', 'FIXTURE_DOCUMENT');
    final clock = Stopwatch()..start();
    final file = File('${root.path}/$name');
    while (!await file.exists()) {
      _check(clock.elapsed < const Duration(minutes: 4), 'FIXTURE_TIMEOUT');
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final value = _read(file.path);
    _check(value['format'] == 1 && value['fixtureId'] == id, 'FIXTURE_ID');
    return value;
  }

  Future<Map<String, Object?>> seed() async {
    final file = File('${root.path}/seed.dpapi');
    _check(
      !FileSystemEntity.isLinkSync(file.path) && file.lengthSync() <= 65536,
      'SEED_CUSTODY',
    );
    final clear = await DpapiProtection().unprotect(
      await file.readAsBytes(),
      utf8.encode('ServerDeck-MCP-fixture\n$id'),
    );
    try {
      final seed = _object(jsonDecode(utf8.decode(clear)));
      _check(
        seed['format'] == 1 &&
            seed['fixtureId'] == id &&
            seed['address'] == '127.0.0.1' &&
            seed['uid'] == 42001 &&
            seed['sshUser'] == 'sdeck' &&
            seed['password'] is String,
        'SEED_ID',
      );
      return seed;
    } finally {
      clear.fillRange(0, clear.length, 0);
    }
  }

  void publish(String name, Map<String, Object?> value) {
    _check(
      const {'workspace.json', 'core-proof.json', 'failed.json'}.contains(name),
      'SIGNAL_NAME',
    );
    final target = File('${root.path}/$name');
    _check(!target.existsSync(), 'SIGNAL_EXISTS');
    final pending = File('${target.path}.pending');
    pending.createSync(exclusive: true);
    pending.writeAsStringSync(jsonEncode(value), flush: true);
    pending.renameSync(target.path);
  }
}

final class _Scenario {
  _Scenario(this.fixture, this.model);
  final _Fixture fixture;
  final ProfileController model;
  final actors = <IndependentMcpActor>[];
  final cases = <String>[];
  AutomationController? owner;
  ServerController? server;

  void done(String code) => cases.add(code);

  Future<Map<String, Object?>> tool(
    IndependentMcpActor actor,
    String suffix,
    Map<String, Object?> args, {
    String? denied,
  }) async {
    final reply = await actor.call('tools/call', {
      'name': 'serverdeck_$suffix',
      'arguments': args,
    });
    _check(!reply.containsKey('error'), 'JSON_RPC_$suffix');
    final result = _object(reply['result']);
    final structured = _object(result['structuredContent']);
    if (denied != null) {
      _check(
        result['isError'] == true &&
            structured['ok'] == false &&
            _object(structured['error'])['code'] == denied,
        'DENIED_$suffix',
      );
      return structured;
    }
    _check(
      result['isError'] != true && structured['ok'] == true,
      'SUCCESS_$suffix',
    );
    return _object(structured['data']);
  }

  Future<IndependentMcpActor> actor(
    String grant,
    bool sdk,
    String marker,
  ) async {
    final result = await IndependentMcpActor.start(
      python: fixture.python,
      repository: fixture.repository,
      fixtureRoot: fixture.root.path,
      grantId: grant,
      sdk: sdk,
      secretMarkers: [marker],
    );
    actors.add(result);
    return result;
  }

  Future<String> grant(
    AutomationController controller,
    String label,
    List<String> scopes,
    List<String> targets,
  ) async {
    await controller.saveGrant({
      'label': label,
      'scopes': scopes,
      'serverIds': targets,
      'lifetimeSeconds': 3600,
    });
    _check(controller.error == null && !controller.canRetry, 'OWNER_GRANT');
    final selected = controller.grants.where((row) => row['label'] == label);
    _check(selected.length == 1, 'OWNER_GRANT_ID');
    return selected.single['id'] as String;
  }

  Future<void> run() async {
    final workspace = model.bootstrap.workspaceId!;
    final client = model.bootstrap.client.trustedClient!;
    final generation = model.bootstrap.client.generation;
    _check(model.profiles.isEmpty, 'EMPTY_WORKSPACE');
    fixture.publish('workspace.json', {
      'format': 1,
      'fixtureId': fixture.id,
      'workspaceId': workspace,
    });
    final seed = await fixture.seed();
    final marker = seed['password'] as String;
    final global = AutomationController(client: client);
    owner = global;
    final authorGrant = await grant(global, 'fixture-author', ['author'], []);
    final author = await actor(authorGrant, false, marker);
    final authorTools = _object((await author.call('tools/list'))['result']);
    final names = (authorTools['tools'] as List)
        .map((row) => _object(row)['name'] as String)
        .toSet();
    _check(
      names.isNotEmpty &&
          names.every((name) => name.startsWith('serverdeck_profiles_')),
      'AUTHOR_ONLY',
    );
    const body = <String, Object?>{
      'format': 1,
      'environment': 'ubuntu24.04-amd64-systemd',
      'parameters': <String, Object?>{},
      'steps': [
        {
          'id': 'motd',
          'kind': 'config_file',
          'resourceId': 'system.motd',
          'values': {'text': 'ServerDeck owned acceptance\n'},
        },
      ],
    };
    final valid = await tool(author, 'profiles_validate', {'body': body});
    _check(valid['valid'] == true, 'VALIDATE');
    final createArgs = {
      'requestId': newRequestId(),
      'name': 'fixture-motd',
      'body': body,
    };
    final created = await tool(author, 'profiles_create', createArgs);
    final replay = await tool(author, 'profiles_create', createArgs);
    _check(
      created['profileId'] == replay['profileId'] &&
          created['digest'] == replay['digest'] &&
          created['revision'] == 1,
      'AUTHOR_REPLAY',
    );
    final profileId = created['profileId'] as String;
    final updated = await tool(author, 'profiles_update', {
      'requestId': newRequestId(),
      'profileId': profileId,
      'expectedRevision': 1,
      'name': 'fixture-motd-two',
      'body': body,
    });
    _check(
      updated['revision'] == 2 && updated['digest'] == created['digest'],
      'METADATA_REVISION',
    );
    await tool(author, 'profiles_update', {
      'requestId': newRequestId(),
      'profileId': profileId,
      'expectedRevision': 1,
      'body': body,
    }, denied: 'REVISION_CONFLICT');
    final comparison = await tool(author, 'profiles_compare', {
      'profileId': profileId,
      'fromRevision': 1,
      'toRevision': 2,
    });
    _check(comparison['changes'] is List, 'COMPARE');
    await author.close();
    actors.remove(author);
    done('empty-workspace-author-cas-replay');

    final enrollment = await fixture.waitDocument('enrolled.json');
    _check(enrollment['workspaceId'] == workspace, 'EXECUTOR_WORKSPACE');
    final serverId = newRequestId(), forbiddenId = newRequestId();
    for (final id in [serverId, forbiddenId]) {
      await model.bootstrap.client.mutate(
        MutationIntent(ApiMethod.profilesCreate, {
          'profileId': id,
          'name': id == serverId ? 'fixture' : 'denied',
          'address': seed['address'],
          'port': seed['port'],
          'sshUser': seed['sshUser'],
          'tags': <String>[],
          'credential': {
            'action': 'replace',
            'kind': 'password',
            'password': marker,
          },
        }),
      );
    }
    final connection = ServerController(client: client, profileId: serverId);
    server = connection;
    await connection.probeTrust();
    _check(
      connection.error == null &&
          connection.trustChallenge?.key.fingerprint == seed['hostFingerprint'],
      'ACTUAL_SSH_PIN',
    );
    await connection.confirmTrust();
    _check(connection.error == null, 'TRUST_CONFIRM');
    await connection.connect();
    _check(
      connection.error == null && connection.connection?.state == 'connected',
      'OWNER_CONNECT',
    );
    await connection.inspectExecutor();
    _check(
      connection.error == null &&
          _object(connection.executorInspection?['enrollment'])['hostId'] ==
              enrollment['hostId'],
      'EXECUTOR_INSPECT',
    );
    await connection.confirmExecutor();
    _check(
      connection.error == null &&
          connection.executor?.hostId == enrollment['hostId'],
      'EXECUTOR_CONFIRM',
    );
    done('actual-owner-trust-connect-enrollment');
    global.dispose();
    final control = AutomationController(client: client, serverId: serverId);
    owner = control;
    const scopes = ['read', 'logs', 'author', 'plan', 'apply'];
    final wireGrant = await grant(control, 'fixture-wire', scopes, [serverId]);
    final sdkGrant = await grant(control, 'fixture-sdk', scopes, [serverId]);
    final wire = await actor(wireGrant, false, marker);
    final sdk = await actor(sdkGrant, true, marker);
    for (final peer in [wire, sdk]) {
      final list = await tool(peer, 'servers_list', {});
      _check(
        (list['items'] as List).length == 1 &&
            _object((list['items'] as List).single)['id'] == serverId,
        'SCOPED_SERVER_LIST',
      );
      await tool(peer, 'server_get', {
        'serverId': forbiddenId,
      }, denied: 'FORBIDDEN');
      await tool(peer, 'server_connect', {'serverId': serverId});
      await tool(peer, 'state_get', {'serverId': serverId, 'refresh': true});
      await tool(peer, 'logs_read', {'serverId': serverId, 'limit': 10});
      final read = await tool(peer, 'profiles_get', {'profileId': profileId});
      _check(_object(read['revision'])['revision'] == 2, 'SHARED_CATALOG');
    }
    done('two-clients-scoped-reads-logs-shared-catalog');
    final wirePlanAck = await tool(wire, 'plan_create', {
      'requestId': newRequestId(),
      'serverId': serverId,
      'profileId': profileId,
      'revision': 1,
      'parameters': <String, Object?>{},
    });
    final wirePlanId = wirePlanAck['planId'] as String;
    final wirePlan = _object(
      (await tool(wire, 'plans_get', {'planId': wirePlanId}))['plan'],
    );
    _check(wirePlan['status'] == 'runnable', 'RUNNABLE_PLAN');
    final applyArgs = {'requestId': newRequestId(), 'planId': wirePlanId};
    await tool(wire, 'apply', applyArgs, denied: 'APPROVAL_REQUIRED');
    await tool(wire, 'approval_request', {
      'requestId': newRequestId(),
      'planId': wirePlanId,
    });
    await control.loadPlan(wirePlanId);
    _check(
      control.error == null && control.plan?['digest'] == wirePlan['digest'],
      'OWNER_SAME_PLAN',
    );
    await control.approvePlan(control.plan!, approve: true);
    _check(control.error == null, 'OWNER_APPROVE');
    final admitted = await tool(wire, 'apply', applyArgs);
    final jobId = admitted['jobId'] as String;
    await successfulJob(wire, jobId);
    final duplicate = await tool(wire, 'apply', applyArgs);
    final samePlan = await tool(wire, 'apply', {
      'requestId': newRequestId(),
      'planId': wirePlanId,
    });
    _check(
      duplicate['jobId'] == jobId && samePlan['jobId'] == jobId,
      'ONE_PLAN_ONE_JOB',
    );
    await control.refreshJobs();
    _check(
      control.error == null &&
          control.jobs.any((row) => _object(row['job'])['id'] == jobId),
      'OWNER_SAME_JOB',
    );
    done('owner-approval-actual-effect-durable-replay');

    final revisionOne = _object(
      (await tool(sdk, 'profiles_get', {
        'profileId': profileId,
        'revision': 1,
      }))['revision'],
    );
    await control.createDelegation(
      displayedRevision: revisionOne,
      grantId: sdkGrant,
      predicates: {},
      lifetimeSeconds: 1800,
    );
    _check(control.error == null, 'DELEGATE_R1');
    final sdkAck = await tool(sdk, 'plan_create', {
      'requestId': newRequestId(),
      'serverId': serverId,
      'profileId': profileId,
      'revision': 2,
      'parameters': <String, Object?>{},
    });
    final sdkPlan = sdkAck['planId'] as String;
    final sdkApply = {'requestId': newRequestId(), 'planId': sdkPlan};
    await tool(sdk, 'apply', sdkApply, denied: 'APPROVAL_REQUIRED');
    final revisionTwo = _object(
      (await tool(sdk, 'profiles_get', {
        'profileId': profileId,
        'revision': 2,
      }))['revision'],
    );
    await control.createDelegation(
      displayedRevision: revisionTwo,
      grantId: sdkGrant,
      predicates: {},
      lifetimeSeconds: 1800,
    );
    _check(control.error == null, 'DELEGATE_R2');
    final secondJob = await tool(sdk, 'apply', sdkApply);
    await successfulJob(sdk, secondJob['jobId'] as String);
    final configuration = await tool(sdk, 'configuration_get', {
      'serverId': serverId,
      'resourceId': 'system.motd',
      'refresh': true,
    });
    _check(
      _object(configuration['comparison'])['status'] == 'matched',
      'DESIRED_OBSERVED_MATCH',
    );
    await connection.readConfiguration('system.motd');
    _check(
      connection.error == null &&
          _object(connection.configuration?['desired'])['lastJobId'] ==
              secondJob['jobId'] &&
          _object(configuration['desired'])['lastJobId'] == secondJob['jobId'],
      'OWNER_SAME_DESIRED',
    );
    done('exact-version-delegation-desired-state');
    await sdk.close();
    actors.remove(sdk);
    await wire.call('ping');
    await tool(wire, 'state_get', {'serverId': serverId});
    _check(
      !client.isClosed && model.bootstrap.client.generation == generation,
      'SDK_CLOSE_SHARED_SERVICE_LIVES',
    );
    done('sdk-job-object-close-keeps-shared-service');
    await control.refreshGrants();
    final selected = control.grants.singleWhere(
      (row) => row['id'] == wireGrant,
    );
    await control.revokeGrant(selected);
    _check(control.error == null, 'OWNER_REVOKE');
    await tool(wire, 'state_get', {'serverId': serverId}, denied: 'FORBIDDEN');
    await control.selectJob(jobId);
    _check(control.error == null, 'OWNER_REVOKED_JOB_READ');
    final previousJob = jsonEncode(control.job);
    await control.jobAction(jobId, reconcile: true);
    _check(
      control.error == null && jsonEncode(control.job) == previousJob,
      'OWNER_REVOKED_JOB_RECONCILE',
    );
    await control.jobAction(jobId, reconcile: false);
    _check(
      control.error == null && jsonEncode(control.job) == previousJob,
      'OWNER_REVOKED_JOB_STOP',
    );
    final deniedOwner = AutomationController(
      client: client,
      serverId: serverId,
    );
    try {
      await deniedOwner.applyPlan(wirePlan);
      _check(deniedOwner.error == 'FORBIDDEN', 'OWNER_CANNOT_REVIVE_GRANT');
    } finally {
      deniedOwner.dispose();
    }
    await wire.close();
    actors.remove(wire);
    done('current-grant-revoke');
    done('owner-control-after-grant-revoke');
    // Published only after all actors actually closed. Full feature acceptance
    // additionally requires recipe/fault/native/migration suites, tracked apart.
    fixture.publish('core-proof.json', {
      'format': 1,
      'fixtureId': fixture.id,
      'sourceSnapshotSha256': fixture.identity['sourceSnapshotSha256'],
      'scenario': 'native-owner-two-independent-mcp-clients',
      'cases': cases,
      'fullAcceptance': false,
    });
  }

  Future<void> successfulJob(IndependentMcpActor actor, String id) async {
    final clock = Stopwatch()..start();
    while (true) {
      final response = await tool(actor, 'jobs_get', {'jobId': id});
      final state = _object(response['job'])['state'];
      if (state == 'succeeded') break;
      _check(
        !const {
          'failed',
          'cancelled',
          'cancelled-partial',
          'unknown',
        }.contains(state),
        'JOB_SUCCESS',
      );
      _check(clock.elapsed < const Duration(minutes: 3), 'JOB_TIMEOUT');
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final events = await tool(actor, 'jobs_events', {
      'jobId': id,
      'limit': 100,
    });
    _check((events['events'] as List).isNotEmpty, 'ACTUAL_JOB_EVENTS');
  }

  Future<void> close() async {
    Object? failed;
    for (final actor in actors.reversed.toList()) {
      try {
        await actor.close();
      } on Object {
        failed = true;
      }
    }
    actors.clear();
    owner?.dispose();
    server?.dispose();
    if (failed != null) throw StateError('MCP_CORE_CLEANUP_FAILED');
  }
}
