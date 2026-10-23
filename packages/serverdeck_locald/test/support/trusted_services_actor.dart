import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/owner_api.dart';
import 'package:serverdeck_locald/api/owner_service_probe.dart';
import 'package:serverdeck_locald/bootstrap/trusted_services.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'trusted_auth_actor.dart' as a;
import 'trusted_grant_actor.dart' as g;
import 'profile_catalog_storage_scenarios.dart' show catalogBody;

String id(int n) => '70000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

String stage = 'setup';
g.PausedProtection? protection;

Future<void> scenario(String root, String mode) => g.scenario(
  root,
  'services-$mode',
  inspectProtection: (value) => protection = value,
  readyRun: (root, store, unusedAuthority, plain, write, advance) async {
    final owner = await a.Pair.start(
      root,
      'serverdeck.exe',
      plain,
      nativeGate: true,
    );
    final sessions = owner.registry;
    final custody = KeyCustody(DpapiProtection(), currentUserSid());
    final key = await custody.openReceiptKey(
      await readProtectedFile(
        p.join(root, 'private'),
        p.join(
          root,
          'private',
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
    TrustedControlServices? services;
    final peers = <a.Pair>[];
    Object? failure;
    StackTrace? trace;
    var expectedCloseFailure = false, next = 100;
    final release = Completer<void>();
    Future<TrustedControlServices> attach({
      TrustedSessions? registry,
      ReceiptKeyMaterial? material,
    }) => TrustedControlServices.create(
      store: store,
      custody: custody,
      receiptKey: material ?? key,
      sessions: registry ?? sessions,
    );
    Future<a.Pair> peer(String image, {bool nativeGate = false}) async {
      final pair = await a.Pair.start(
        root,
        image,
        sessions,
        nativeGate: nativeGate,
      );
      peers.add(pair);
      await pair.exchange();
      a.check(
        await pair.next() == (image == 'mcp.exe' ? 'AUTH:mcp' : 'AUTH:owner'),
      );
      return pair;
    }

    try {
      await owner.exchange();
      a.check(await owner.next() == 'AUTH:owner');
      final baseline = store.trustedOperational.preservationDigest();
      if (mode == 'prerequisites') {
        await a.fails(attach(registry: plain), 'NOT_READY');
        final wrong = await custody.createReceiptKey(g.workspaceId, g.keyId);
        try {
          await a.fails(attach(material: wrong), 'STORAGE_BLOCKED');
        } finally {
          wrong.close();
        }
        a.check(baseline == store.trustedOperational.preservationDigest());
      }
      final control = services = await attach();
      if (mode == 'ordinary') {
        await a.fails(
          Future.sync(sessions.observeNextAuthorityAcquisitionForTest),
          'UNSUPPORTED',
        );
        await a.fails(
          Future.sync(() => OwnerServiceProbe.install((_, __) async {})),
          'OWNER_PROBE_UNAVAILABLE',
        );
        return;
      }
      Future<Map<String, Object?>> call(
        String method,
        Map<String, Object?> body, {
        String? requestId,
      }) async {
        stage = method;
        final request = await sessions.begin(
          owner.channel,
          owner.response!.sessionId,
          method,
        );
        try {
          return await control.dispatch(
            request,
            method,
            body,
            requestId: requestId ?? id(next++),
          );
        } finally {
          request.complete();
        }
      }

      Map<String, Object?> grant(
        String request,
        String target, {
        int? revision,
        bool revoke = false,
      }) => {
        'requestId': request,
        'grantId': target,
        if (revision != null) 'expectedRevision': revision,
        if (!revoke) ...{
          'label': 'Owned fixture',
          'scopes': ['author'],
          'serverIds': <String>[],
        },
      };
      Future<a.Pair> openedMcp() async {
        final pair = await peer('mcp.exe');
        final params = await g.signedParams(root, pair);
        final request = await sessions.begin(
          pair.channel,
          pair.response!.sessionId,
          'mcp.open',
        );
        try {
          await request.openGrant(control.authority, params);
        } finally {
          request.complete();
        }
        return pair;
      }

      Future<Map<String, Object?>> tool(
        a.Pair pair,
        String operation,
        Map<String, Object?> arguments,
      ) async {
        stage = 'tool:$operation';
        Future<McpInvokeReply> invoke(Map<String, Object?> params) async {
          final request = await sessions.begin(
            pair.channel,
            pair.response!.sessionId,
            'mcp.invoke',
          );
          try {
            return await control.router.invoke(request, params);
          } finally {
            request.complete();
          }
        }

        var reply = await invoke({
          'request': {
            'name': 'serverdeck_profiles_$operation',
            'arguments': arguments,
          },
        });
        final watch = Stopwatch()..start();
        while (reply.kind == McpInvokeReplyKind.pending) {
          a.check(watch.elapsed < const Duration(seconds: 4));
          await Future<void>.delayed(const Duration(milliseconds: 5));
          reply = await invoke({
            'poll': {'operationId': reply.toJson()['operationId']},
          });
        }
        a.check(reply.kind == McpInvokeReplyKind.done);
        final result =
            (reply.toJson()['result'] as Map)['structuredContent'] as Map;
        if (result['ok'] != true)
          throw StateError((result['error'] as Map)['code']);
        return Map<String, Object?>.from(result['data'] as Map);
      }

      if (mode == 'prerequisites') {
        await a.fails(attach(), 'NOT_READY');
        final other = await peer('serverdeck.exe', nativeGate: true);
        await a.fails(attach(registry: other.registry), 'NOT_READY');
        await other.registry.close();
        await control.close();
        final fresh = await peer('serverdeck.exe', nativeGate: true);
        final replacement = await attach(registry: fresh.registry);
        await replacement.close();
        a.check(baseline == store.trustedOperational.preservationDigest());
        store.assertAutomationCustody(custody, key);
        return;
      }
      if (mode == 'basic') {
        final methods = <String>[
          for (final operation in ['list', 'get', 'create', 'update', 'delete'])
            'profiles.$operation',
          'settings.get',
          'settings.update',
          'mutations.get',
          'mutations.recent',
          for (final operation in ['create', 'replace', 'revoke'])
            'grants.$operation',
          for (final operation in [
            'list',
            'get',
            'create',
            'update',
            'compare',
            'validate',
            'archive',
          ])
            'automation.profiles.$operation',
          for (final operation in [
            'get',
            'probe',
            'probeStatus',
            'probeCancel',
            'confirm',
            'revoke',
          ])
            'servers.trust.$operation',
        ];
        a.check(
          methods.length == 25 &&
              methods.every(control.supports) &&
              !control.supports('arbitrary.shell'),
        );
        final bad = await sessions.begin(
          owner.channel,
          owner.response!.sessionId,
          'settings.get',
        );
        try {
          await a.fails(
            Future.sync(
              () => control.prepare(bad, 'settings.update', {
                'invalid': true,
              }, requestId: 'bad'),
            ),
            'FORBIDDEN',
          );
        } finally {
          bad.complete();
        }
        final foreign = await a.Pair.start(root, 'serverdeck.exe', plain);
        peers.add(foreign);
        await foreign.exchange();
        a.check(await foreign.next() == 'AUTH:owner');
        final foreignRequest = await plain.begin(
          foreign.channel,
          foreign.response!.sessionId,
          'settings.get',
        );
        try {
          await a.fails(
            Future.sync(
              () => control.prepare(foreignRequest, 'settings.get', {
                'invalid': true,
              }, requestId: 'bad'),
            ),
            'FORBIDDEN',
          );
        } finally {
          foreignRequest.complete();
        }
        await a.fails(
          call('arbitrary.shell', {'invalid': true}),
          'UNSUPPORTED',
        );
        final target = id(8000), commit = id(8001);
        final fields = {
          'name': 'Owned target',
          'address': 'fixture.invalid',
          'port': 22,
          'sshUser': 'fixture',
          'tags': <String>[],
          'credential': {'action': 'remove'},
        };
        await call('profiles.create', {
          'profileId': target,
          ...fields,
        }, requestId: commit);
        a.check((await call('profiles.list', {}))['profiles'] is List);
        a.check(
          ((await call('profiles.get', {'profileId': target}))['profile']
                  as Map)['revision'] ==
              '1',
        );
        a.check(
          (await call('mutations.get', {'requestId': commit}))['state'] ==
              'committed',
        );
        a.check((await call('mutations.recent', {}))['receipts'] is List);
        a.check(
          (await call('servers.trust.get', {'profileId': target}))['trust'] ==
              null,
        );
        final create = await call('automation.profiles.create', {
          'requestId': id(next++),
          'name': 'Shared catalog',
          'body': catalogBody(),
        });
        final catalogId = create['profileId'];
        await call('automation.profiles.update', {
          'requestId': id(next++),
          'profileId': catalogId,
          'expectedRevision': 1,
          'body': catalogBody(),
        });
        var mcp = await openedMcp();
        final denied = await sessions.begin(
          mcp.channel,
          mcp.response!.sessionId,
          'session.ping',
        );
        try {
          await a.fails(
            Future.sync(
              () => control.prepare(denied, 'session.ping', {
                'invalid': true,
              }, requestId: 'bad'),
            ),
            'FORBIDDEN',
          );
        } finally {
          denied.complete();
        }
        a.check(
          (await tool(mcp, 'get', {'profileId': catalogId}))['revision'] is Map,
        );
        final second = await tool(mcp, 'create', {
          'requestId': id(next++),
          'name': 'MCP authored',
          'body': catalogBody(),
        });
        a.check((await tool(mcp, 'list', {}))['items'] is List);
        await tool(mcp, 'compare', {
          'profileId': catalogId,
          'fromRevision': 1,
          'toRevision': 2,
        });
        await tool(mcp, 'archive', {
          'requestId': id(next++),
          'profileId': second['profileId'],
          'expectedRevision': 1,
        });
        final settings = (await call('settings.get', {}))['settings'] as Map;
        await call('settings.update', {
          'expectedRevision': settings['revision'],
          'theme': 'dark',
          'reduceMotion': true,
          'selectedProfileId': null,
        });
        a.check(
          (await tool(mcp, 'validate', {'body': catalogBody()}))['valid'] ==
              true,
        );
        await tool(mcp, 'update', {
          'requestId': id(next++),
          'profileId': catalogId,
          'expectedRevision': 2,
          'body': catalogBody(),
        });
        a.check(
          ((await call('automation.profiles.get', {
                    'profileId': catalogId,
                  }))['revision']
                  as Map)['revision'] ==
              3,
        );
        await call('automation.profiles.list', {});
        await call('automation.profiles.compare', {
          'profileId': catalogId,
          'fromRevision': 1,
          'toRevision': 3,
        });
        await call('automation.profiles.validate', {'body': catalogBody()});
        await call('automation.profiles.archive', {
          'requestId': id(next++),
          'profileId': catalogId,
          'expectedRevision': 3,
        });
        a.check(
          ((await tool(mcp, 'get', {'profileId': catalogId}))['profile']
                  as Map)['archived'] ==
              true,
        );
        await call('profiles.update', {
          'profileId': target,
          'expectedRevision': '1',
          ...fields,
          'name': 'Changed metadata',
        });
        await a.fails(tool(mcp, 'list', {}), 'UNAUTHORIZED');
        mcp = await openedMcp();
        final newGrant = id(8100);
        await call('grants.create', grant(id(next++), newGrant));
        await call('grants.replace', grant(id(next++), newGrant, revision: 1));
        await call(
          'grants.revoke',
          grant(id(next++), newGrant, revision: 2, revoke: true),
        );
        await call('grants.replace', grant(id(next++), g.grantId, revision: 4));
        await a.fails(tool(mcp, 'list', {}), 'UNAUTHORIZED');
        mcp = await openedMcp();
        await call(
          'grants.revoke',
          grant(id(next++), g.grantId, revision: 5, revoke: true),
        );
        await a.fails(tool(mcp, 'list', {}), 'UNAUTHORIZED');
        await call('profiles.delete', {
          'profileId': target,
          'expectedRevision': '2',
        });
        a.check(store.isTrustedSnapshotLoaded);
        return;
      }
      if (mode == 'grant-drain') {
        final mcp = await peer('mcp.exe');
        final params = await g.signedParams(root, mcp);
        final request = await sessions.begin(
          mcp.channel,
          mcp.response!.sessionId,
          'mcp.open',
        );
        try {
          protection!.pauseNext = 1;
          final work = request.openGrant(control.authority, params);
          work.ignore();
          await protection!.reached(1);
          final closing = control.close();
          var closed = false;
          closing.then<void>((_) => closed = true).ignore();
          await a.fails(work, 'UNAUTHORIZED');
          await Future<void>.delayed(const Duration(milliseconds: 40));
          a.check(
            !closed &&
                control.authority.pendingOpens == 1 &&
                store.isTrustedSnapshotLoaded,
          );
          store.assertAutomationCustody(custody, key);
          protection!.release();
          await closing;
          a.check(
            closed &&
                protection!.cleartexts.every(
                  (bytes) => bytes.every((v) => v == 0),
                ),
          );
        } finally {
          request.complete();
        }
        return;
      }
      if (mode == 'write-drain' || mode == 'native-failure') {
        final reached = Completer<void>();
        OwnerServiceProbe.install((boundary, method) async {
          if (boundary == OwnerServiceBoundary.afterFoundationCommit &&
              method == 'settings.update') {
            reached.complete();
            await release.future;
          }
        });
        if (mode == 'native-failure')
          sessions.failNextAuthorityLeaseReleaseForTest();
        final settings = store.state.settings;
        final work = call('settings.update', {
          'expectedRevision': settings.revision,
          'theme': 'dark',
          'reduceMotion': true,
          'selectedProfileId': null,
        });
        work.ignore();
        await reached.future.timeout(const Duration(seconds: 3));
        final closing = control.close();
        var closed = false;
        closing
            .then<void>(
              (_) => closed = true,
              onError: (Object _) {
                closed = true;
              },
            )
            .ignore();
        await Future<void>.delayed(const Duration(milliseconds: 40));
        a.check(!closed && store.state.settings.theme.name == 'dark');
        store.assertAutomationCustody(custody, key);
        if (mode == 'native-failure') {
          expectedCloseFailure = true;
          release.complete();
          await a.fails(work, 'SERVICE_UNAVAILABLE');
          await a.fails(closing, 'SERVICE_UNAVAILABLE');
          final fresh = await TrustedSessions.withNativePublicationGate(
            generation: id(8999),
            peer: owner.peer!,
          );
          try {
            await a.fails(attach(registry: fresh), 'NOT_READY');
          } finally {
            await fresh.close();
          }
          store.assertAutomationCustody(custody, key);
        } else {
          release.complete();
          await work;
          await closing;
        }
        a.check(closed);
        return;
      }
      if (mode == 'proof-drain' ||
          mode.startsWith('native-') ||
          mode == 'probe-drain') {
        final probe = mode == 'probe-drain';
        if (probe) {
          await call('profiles.create', {
            'profileId': id(8200),
            'name': 'Probe target',
            'address': '127.0.0.1',
            'port': 1,
            'sshUser': 'fixture',
            'tags': <String>[],
            'credential': {'action': 'remove'},
          });
        }
        final method = probe
            ? 'servers.trust.probe'
            : mode == 'proof-drain'
            ? 'automation.profiles.list'
            : 'automation.profiles.create';
        final request = await sessions.begin(
          owner.channel,
          owner.response!.sessionId,
          method,
        );
        final observation = mode == 'proof-drain' || probe
            ? await owner.peer!.observeNextRevalidationForTest()
            : sessions.observeNextAuthorityAcquisitionForTest();
        try {
          final work = control.dispatch(
            request,
            method,
            probe
                ? {'profileId': id(8200), 'expectedRevision': '1'}
                : mode == 'proof-drain'
                ? {}
                : {
                    'requestId': id(next++),
                    'name': 'Pending catalog',
                    'body': catalogBody(),
                  },
            requestId: id(next++),
          );
          work.ignore();
          await observation.reached.timeout(const Duration(seconds: 3));
          if (probe) {
            a.check((await work)['state'] == 'running');
          } else {
            await a.fails(work, 'TIMEOUT');
          }
          final closing = control.close();
          var closed = false;
          closing
              .then<void>(
                (_) => closed = true,
                onError: (Object _) {
                  closed = true;
                },
              )
              .ignore();
          await Future<void>.delayed(const Duration(milliseconds: 40));
          a.check(!closed && store.isTrustedSnapshotLoaded);
          store.assertAutomationCustody(custody, key);
          await observation.release();
          await closing;
          a.check(
            closed && store.trustedOperational.automation.profiles.isEmpty,
          );
          a.check(identical(closing, control.close()));
        } finally {
          await observation.release();
          request.complete();
        }
        return;
      }
      final request = sessions.reserve(
        owner.channel,
        owner.response!.sessionId,
        'grants.create',
      );
      final before = store.trustedOperational.preservationDigest();
      final invocation = control.prepare(request, 'grants.create', {
        'requestId': id(1),
        'grantId': id(2),
        'label': 'Owned fixture',
        'scopes': ['author'],
        'serverIds': <String>[],
      }, requestId: id(3));
      final settingsRequest = sessions.reserve(
        owner.channel,
        owner.response!.sessionId,
        'settings.update',
      );
      final settingsInvocation = control.prepare(
        settingsRequest,
        'settings.update',
        {
          'expectedRevision': store.state.settings.revision,
          'theme': 'dark',
          'reduceMotion': true,
          'selectedProfileId': null,
        },
        requestId: id(4),
      );
      final trustRequest = sessions.reserve(
        owner.channel,
        owner.response!.sessionId,
        'servers.trust.revoke',
      );
      final trustInvocation = control.prepare(
        trustRequest,
        'servers.trust.revoke',
        {'profileId': id(2), 'expectedRevision': '1'},
        requestId: id(5),
      );
      try {
        for (final prepared in [
          invocation,
          settingsInvocation,
          trustInvocation,
        ]) {
          await a.fails(prepared.execute(), 'FORBIDDEN');
        }
        final closing = control.close();
        a.check(identical(closing, control.close()));
        await closing;
        for (final prepared in [
          invocation,
          settingsInvocation,
          trustInvocation,
        ]) {
          await a.fails(prepared.execute(), 'SERVICE_UNAVAILABLE');
        }
        a.check(before == store.trustedOperational.preservationDigest());
        a.check(sessions.count == 0 && control.authority.pendingOpens == 0);
        store.assertAutomationCustody(custody, key);
        a.check(identical(closing, control.close()));
      } finally {
        invocation.close();
        request.complete();
        settingsInvocation.close();
        settingsRequest.complete();
        trustInvocation.close();
        trustRequest.complete();
      }
    } catch (error, stack) {
      failure = error;
      trace = stack;
    } finally {
      protection!.release();
      if (!release.isCompleted) release.complete();
      for (final cleanup in <Future<void> Function()>[
        () async {
          if (services == null) return;
          if (expectedCloseFailure) {
            await a.fails(services.close(), 'SERVICE_UNAVAILABLE');
          } else {
            await services.close();
          }
        },
        () async {
          if (expectedCloseFailure) {
            await a.fails(sessions.close(), 'SERVICE_UNAVAILABLE');
          } else {
            await sessions.close();
          }
        },
        for (final pair in peers)
          () async {
            if (!identical(pair.registry, sessions))
              await pair.registry.close();
            await pair.close();
          },
        owner.close,
        () async => key.close(),
      ]) {
        try {
          await cleanup();
        } catch (error, stack) {
          failure ??= error;
          trace ??= stack;
        }
      }
      if (failure != null) Error.throwWithStackTrace(failure, trace!);
    }
  },
);

Future<void> main(List<String> args) async {
  try {
    containCurrentFixtureTree();
    if (args.first == 'client') {
      await a.client(args);
      return;
    }
    a.ownRoot(args[0]);
    await scenario(args[0], args[1]);
    stdout.writeln('PASS:${args[1]}');
  } catch (error, stack) {
    stderr.writeln('SERVICES_FIXTURE_FAILED:$stage:${error.runtimeType}');
    stderr.writeln(stack.toString().split('\n').take(8).join('\n'));
    exitCode = 1;
  }
}
