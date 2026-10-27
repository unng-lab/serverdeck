import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/operational_server.dart';
import 'package:serverdeck_locald/api/owner_grants.dart';
import 'package:serverdeck_locald/api/owner_profiles.dart';
import 'package:serverdeck_locald/automation/profiles.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'trusted_auth_actor.dart' as a;
import 'trusted_grant_actor.dart' as g;
import 'profile_catalog_actor.dart' show cleanupCatalogFixture;
import 'profile_catalog_storage_scenarios.dart' show catalogBody;
import 'trusted_foundation_owner_scenarios.dart';
import 'trust_probe_scenarios.dart';

Future<void> scenario(String root, String mode) => g.scenario(
  root,
  'owner-$mode',
  readyRun: (root, store, authority, plain, write, advance) async {
    var nativeProbeTime = Duration.zero;
    final owner = await a.Pair.start(
      root,
      'serverdeck.exe',
      plain,
      nativeGate: true,
      clock:
          mode == 'probe-success-deadline' ||
              mode == 'probe-admission-clock' ||
              mode == 'probe-success-write-clock'
          ? () => nativeProbeTime
          : null,
    );
    final sessions = owner.registry;
    final custody = KeyCustody(DpapiProtection(), currentUserSid());
    final local = p.join(root, 'private');
    final key = await custody.openReceiptKey(
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
    TrustedAutomationProfileService? service;
    a.Pair? foreign;
    var counter = 0;
    String id() =>
        '92345678-1234-4234-8234-${(++counter).toString().padLeft(12, '0')}';
    const grantId = '82345678-1234-4234-8234-123456789abc';
    Map<String, Object?> create() => {
      'requestId': id(),
      'grantId': grantId,
      'label': 'Owner fixed input',
      'scopes': ['author'],
      'serverIds': <String>[],
      'lifetimeSeconds': 300,
    };
    try {
      await owner.exchange();
      a.check(await owner.next() == 'AUTH:owner');
      if (mode.startsWith('probe-')) {
        await exerciseTrustProbes(
          root,
          mode,
          store,
          custody,
          key,
          owner,
          plain,
          advanceNative: (value) => nativeProbeTime = value,
        );
        return;
      }
      if (mode.startsWith('foundation-')) {
        await exerciseTrustedFoundationOwner(
          root,
          mode,
          store,
          custody,
          key,
          owner,
          plain,
        );
        return;
      }
      if (mode == 'gate') {
        await a.fails(
          Future.sync(
            () => TrustedGrantOwnerApi(store: store, sessions: plain),
          ),
          'NOT_READY',
        );
        a.check(store.isTrustedSnapshotLoaded);
        return;
      }
      final catalog = service = TrustedAutomationProfileService(
        store: store,
        custody: custody,
        receiptKey: key,
        sessions: sessions,
        authority: authority,
      );
      final grants = TrustedGrantOwnerApi(store: store, sessions: sessions);
      final profiles = TrustedProfileOwnerApi(catalog);
      final group = TrustedOwnerApiGroup([grants, profiles]);
      Future<TrustedSessionRequest> request(String method) =>
          sessions.begin(owner.channel, owner.response!.sessionId, method);
      Future<Map<String, Object?>> dispatch(
        String method,
        Map<String, Object?> params,
      ) async {
        final interest = await request(method);
        try {
          return await group.dispatch(
            interest,
            method,
            params,
            requestId: id(),
          );
        } finally {
          interest.complete();
        }
      }

      if (mode == 'role' || mode == 'foreign') {
        final mcp = mode == 'role';
        final pair = foreign = await a.Pair.start(
          root,
          mcp ? 'mcp.exe' : 'serverdeck.exe',
          mcp ? sessions : plain,
        );
        await pair.exchange();
        a.check(await pair.next() == (mcp ? 'AUTH:mcp' : 'AUTH:owner'));
        final method = mcp ? 'session.ping' : 'grants.create';
        final interest = await (mcp ? sessions : plain).begin(
          pair.channel,
          pair.response!.sessionId,
          method,
        );
        try {
          await a.fails(
            Future.sync(
              () => grants.prepare(interest, method, {
                'invalid': 'before parse',
              }, requestId: id()),
            ),
            'FORBIDDEN',
          );
          await a.fails(
            Future.sync(
              () => profiles.prepare(interest, method, {
                'invalid': 'before parse',
              }, requestId: id()),
            ),
            'FORBIDDEN',
          );
          await a.fails(
            Future.sync(
              () => group.prepare(interest, method, {
                'invalid': 'before parse',
              }, requestId: id()),
            ),
            'FORBIDDEN',
          );
        } finally {
          interest.complete();
        }
        return;
      }
      if (mode == 'groups') {
        final interest = await request('grants.create');
        try {
          await a.fails(
            Future.sync(
              () =>
                  TrustedOwnerApiGroup([])
                      .prepare(interest, 'grants.create', {}, requestId: id()),
            ),
            'UNSUPPORTED',
          );
          await a.fails(
            Future.sync(
              () =>
                  TrustedOwnerApiGroup([grants, grants])
                      .prepare(interest, 'grants.create', {}, requestId: id()),
            ),
            'INTERNAL',
          );
          a.check(
            group.supports('grants.create') &&
                group.supports('automation.profiles.validate') &&
                !group.supports('unknown'),
          );
        } finally {
          interest.complete();
        }
        return;
      }
      if (mode == 'admission') {
        final interest = sessions.reserve(
          owner.channel,
          owner.response!.sessionId,
          'grants.create',
        );
        final input = create();
        final prepared = grants.prepare(
          interest,
          'grants.create',
          input,
          requestId: id(),
        );
        try {
          await a.fails(prepared.execute(), 'FORBIDDEN');
          a.check(
            !store.trustedOperational.automation.grants.containsKey(grantId),
          );
          input['label'] = 'Changed after prepare';
          (input['scopes'] as List).add('read');
          await sessions.completeAdmission(interest);
          final work = prepared.execute();
          a.check(identical(work, prepared.execute()));
          await work;
          final saved = store.trustedOperational.automation.grants[grantId]!;
          a.check(
            saved.label == 'Owner fixed input' &&
                saved.policy.scopes.length == 1,
          );
          prepared.close();
          prepared.close();
          await a.fails(prepared.execute(), 'SERVICE_UNAVAILABLE');
        } finally {
          prepared.close();
          interest.complete();
        }
        return;
      }
      if (mode == 'profile-admission') {
        final interest = sessions.reserve(
          owner.channel,
          owner.response!.sessionId,
          'automation.profiles.create',
        );
        final body = catalogBody();
        final input = {
          'requestId': id(),
          'name': 'Captured profile',
          'body': body,
        };
        final prepared = profiles.prepare(
          interest,
          'automation.profiles.create',
          input,
          requestId: id(),
        );
        try {
          await a.fails(prepared.execute(), 'FORBIDDEN');
          a.check(store.trustedOperational.automation.profiles.isEmpty);
          input['name'] = 'Changed after prepare';
          body['environment'] = 'invalid after prepare';
          await sessions.completeAdmission(interest);
          final work = prepared.execute();
          a.check(identical(work, prepared.execute()));
          final result = await work;
          final profile = result['profileId'] as String;
          a.check(
            store.trustedOperational.automation.profiles[profile]!.name ==
                'Captured profile',
          );
          a.check(
            store.trustedOperational.automation.revisions['$profile:1']!.body
                    .toJson()['environment'] ==
                'ubuntu24.04-amd64-systemd',
          );
        } finally {
          prepared.close();
          interest.complete();
        }
        return;
      }
      if (mode == 'invocation') {
        final interest = await request('session.ping');
        var effects = 0, closed = 0;
        final prepared = TrustedOwnerInvocation(
          interest,
          () async {
            effects++;
            return {'done': true};
          },
          onClose: () {
            closed++;
          },
        );
        try {
          final work = prepared.execute();
          a.check(identical(work, prepared.execute()));
          a.check((await work)['done'] == true && effects == 1);
          prepared.close();
          prepared.close();
          a.check(closed == 1);
          await a.fails(prepared.execute(), 'SERVICE_UNAVAILABLE');
        } finally {
          prepared.close();
          interest.complete();
        }
        return;
      }
      if (mode == 'queued-retired') {
        final gate = await owner.peer!.publicationGate(a.generation);
        final held = await gate.acquire();
        final interest = await request('grants.create');
        final prepared = grants.prepare(
          interest,
          'grants.create',
          create(),
          requestId: id(),
        );
        try {
          final work = prepared.execute();
          work.ignore();
          interest.complete();
          await held.close();
          await a.fails(work, 'UNAUTHORIZED');
          a.check(
            !store.trustedOperational.automation.grants.containsKey(grantId),
          );
        } finally {
          prepared.close();
          interest.complete();
          await held.close();
          await gate.close();
        }
        return;
      }
      if (mode == 'profile-close') {
        final interest = await request('automation.profiles.create');
        final input = {
          'requestId': id(),
          'name': 'Must stay absent',
          'body': catalogBody(),
        };
        final prepared = profiles.prepare(
          interest,
          'automation.profiles.create',
          input,
          requestId: id(),
        );
        try {
          profiles.close();
          profiles.close();
          await a.fails(prepared.execute(), 'NOT_READY');
          await a.fails(
            Future.sync(
              () => profiles.prepare(
                interest,
                'automation.profiles.create',
                input,
                requestId: id(),
              ),
            ),
            'NOT_READY',
          );
          a.check(store.trustedOperational.automation.profiles.isEmpty);
        } finally {
          prepared.close();
          interest.complete();
        }
        return;
      }
      final input = create();
      a.check((await dispatch('grants.create', input))['revision'] == 1);
      a.check((await dispatch('grants.create', input))['revision'] == 1);
      await dispatch('grants.replace', {...create(), 'expectedRevision': 1});
      await dispatch('grants.revoke', {
        'requestId': id(),
        'grantId': grantId,
        'expectedRevision': 2,
      });
      a.check(
        store.trustedOperational.automation.grants[grantId]!.revokedAt != null,
      );
      final created = await dispatch('automation.profiles.create', {
        'requestId': id(),
        'name': 'Owner catalog',
        'body': catalogBody(),
      });
      final profile = created['profileId'] as String;
      await dispatch('automation.profiles.update', {
        'requestId': id(),
        'profileId': profile,
        'expectedRevision': 1,
        'body': catalogBody(),
      });
      a.check(
        (await dispatch('automation.profiles.list', {}))['items'] is List,
      );
      a.check(
        (await dispatch('automation.profiles.get', {
              'profileId': profile,
            }))['revision']
            is Map,
      );
      a.check(
        (await dispatch('automation.profiles.compare', {
              'profileId': profile,
              'fromRevision': 1,
              'toRevision': 2,
            }))['changes']
            is List,
      );
      a.check(
        (await dispatch('automation.profiles.validate', {
              'body': catalogBody(),
            }))['valid'] ==
            true,
      );
      await dispatch('automation.profiles.archive', {
        'requestId': id(),
        'profileId': profile,
        'expectedRevision': 2,
      });
      a.check(store.trustedOperational.automation.profiles[profile]!.archived);
    } finally {
      await cleanupCatalogFixture([
        () async => service?.close(),
        sessions.close,
        () async => foreign?.close(),
        owner.close,
        () async => key.close(),
      ]);
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
    await scenario(args[0], args[1]);
    stdout.writeln('PASS:${args[1]}');
  } catch (error) {
    stderr.writeln('TRUSTED_OWNER_FIXTURE_FAILED:${error.runtimeType}');
    exitCode = 1;
  }
}
