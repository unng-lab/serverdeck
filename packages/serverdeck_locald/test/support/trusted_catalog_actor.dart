import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/automation/profiles.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../../../serverdeck_windows/test/support/native_fixture_job.dart';
import 'trusted_auth_actor.dart' as a;
import 'trusted_grant_actor.dart' as g;
import 'profile_catalog_storage_scenarios.dart' show catalogBody;

String _stage = 'setup';

Future<void> _cleanup(List<Future<void> Function()> actions) async {
  Object? failure;
  StackTrace? trace;
  for (final action in actions) {
    try {
      await action();
    } catch (error, stack) {
      failure ??= error;
      trace ??= stack;
    }
  }
  if (failure != null) Error.throwWithStackTrace(failure, trace!);
}

Future<void> scenario(String root, String mode) => g.scenario(
  root,
  'catalog-$mode',
  readyRun: (root, store, authority, plain, write, advance) async {
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
    a.Pair? mcp;
    TrustedAutomationProfileService? service;
    var expectGateCloseFailure = false;
    var now = DateTime.now().toUtc(), next = 0;
    String requestId() =>
        '72345678-1234-4234-8234-${(++next).toString().padLeft(12, '0')}';
    TrustedAutomationProfileService create(TrustedSessions registry) =>
        TrustedAutomationProfileService(
          store: store,
          custody: custody,
          receiptKey: key,
          sessions: registry,
          authority: authority,
          clock: () => now,
        );
    try {
      await owner.exchange();
      a.check(await owner.next() == 'AUTH:owner');
      if (mode == 'gate') {
        await a.fails(Future.sync(() => create(plain)), 'NOT_READY');
        a.check(store.isTrustedSnapshotLoaded);
        return;
      }
      if (mode == 'custody') {
        final wrong = await custody.createReceiptKey(g.workspaceId, g.keyId);
        try {
          await a.fails(
            Future.sync(
              () => TrustedAutomationProfileService(
                store: store,
                custody: custody,
                receiptKey: wrong,
                sessions: sessions,
                authority: authority,
              ),
            ),
            'STORAGE_BLOCKED',
          );
          a.check(store.isTrustedSnapshotLoaded);
        } finally {
          wrong.close();
        }
        return;
      }
      final catalog = service = create(sessions);
      final peer = mcp = await a.Pair.start(root, 'mcp.exe', sessions);
      await peer.exchange();
      a.check(await peer.next() == 'AUTH:mcp');
      final params = await g.signedParams(root, peer);
      final opening = await sessions.begin(
        peer.channel,
        peer.response!.sessionId,
        'mcp.open',
      );
      await opening.openGrant(authority, params);
      opening.complete();
      final invocation = await sessions.begin(
        peer.channel,
        peer.response!.sessionId,
        'mcp.invoke',
      );
      final context = await invocation.mcpContextWhenStable();
      invocation.complete();
      Future<Map<String, Object?>> asOwner(
        String operation,
        Map<String, Object?> input,
      ) async {
        _stage = 'owner:$operation';
        final request = await sessions.begin(
          owner.channel,
          owner.response!.sessionId,
          'automation.profiles.$operation',
        );
        try {
          return await catalog
              .start(
                catalog.ownerActor(request, operation),
                ProfileCatalogInput.parse(operation, input),
              )
              .result;
        } finally {
          request.complete();
        }
      }

      Future<Map<String, Object?>> asMcp(
        String operation,
        Map<String, Object?> input,
      ) {
        _stage = 'mcp:$operation';
        return catalog
            .start(
              catalog.mcpActor(context, operation),
              ProfileCatalogInput.capture(operation, input),
            )
            .result;
      }

      final createInput = <String, Object?>{
        'requestId': requestId(),
        'name': 'Native trusted catalog',
        'body': catalogBody(),
      };
      if (mode.startsWith('physical-')) {
        final proof = mode.startsWith('physical-proof');
        final failure = mode.endsWith('-failure');
        final observation = proof
            ? await peer.peer!.observeNextRevalidationForTest()
            : sessions.observeNextAuthorityAcquisitionForTest();
        List<int>? originalManifest;
        final manifest = File(p.join(root, 'foundation.manifest.json'));
        try {
          final work = asMcp(
            proof ? 'list' : 'create',
            proof ? {} : createInput,
          );
          work.ignore();
          await observation.reached.timeout(const Duration(seconds: 3));
          await a.fails(work, 'TIMEOUT');
          final closing = catalog.close();
          closing.ignore();
          a.check(identical(closing, catalog.close()));
          var settled = false;
          unawaited(
            closing.then<void>(
              (_) => settled = true,
              onError: (Object _) {
                settled = true;
              },
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 40));
          a.check(
            !settled && store.trustedOperational.automation.profiles.isEmpty,
          );
          if (failure) {
            originalManifest = manifest.readAsBytesSync();
            manifest.writeAsBytesSync([...originalManifest, 10]);
          }
          await observation.release();
          if (failure) {
            await a.fails(closing, 'SERVICE_UNAVAILABLE');
            expectGateCloseFailure = !proof;
          } else {
            await closing;
          }
          service = null; // The completed close (possibly failed) was observed.
          a.check(
            settled && store.trustedOperational.automation.profiles.isEmpty,
          );
        } finally {
          if (originalManifest != null)
            manifest.writeAsBytesSync(originalManifest);
          await observation.release();
        }
        return;
      }
      final created = await asOwner('create', createInput),
          id = created['profileId'] as String;
      a.check((await asOwner('create', createInput))['profileId'] == id);
      if (mode == 'revoke' || mode == 'replace') {
        await write(mode == 'revoke' ? 'grant.revoke' : 'grant.replace');
        await a.fails(
          asMcp('validate', {'invalid': 'must not parse'}),
          'UNAUTHORIZED',
        );
        a.check((await asOwner('get', {'profileId': id}))['profile'] is Map);
        return;
      }
      if (mode == 'foreign') {
        final other = create(sessions);
        final request = await sessions.begin(
          owner.channel,
          owner.response!.sessionId,
          'automation.profiles.list',
        );
        try {
          final actor = other.ownerActor(request, 'list');
          await a.fails(
            Future.sync(
              () => catalog.start(actor, ProfileCatalogInput.parse('list', {})),
            ),
            'FORBIDDEN',
          );
          await a.fails(
            Future.sync(
              () => catalog.start(
                other.mcpActor(context, 'list'),
                ProfileCatalogInput.capture('list', {}),
              ),
            ),
            'FORBIDDEN',
          );
        } finally {
          request.complete();
          await other.close();
        }
        return;
      }
      await asMcp('create', {
        'requestId': requestId(),
        'name': 'Second profile',
        'body': catalogBody(),
      });
      final page = await asOwner('list', {'limit': 1});
      final token = page['nextCursor'] as String;
      a.check(
        (await asOwner('list', {'limit': 1, 'cursor': token}))['items'] is List,
      );
      await a.fails(
        asMcp('list', {'limit': 1, 'cursor': token}),
        'CURSOR_EXPIRED',
      );
      if (mode == 'cursor') {
        now = now.add(const Duration(minutes: 5));
        await a.fails(
          asOwner('list', {'limit': 1, 'cursor': token}),
          'CURSOR_EXPIRED',
        );
        return;
      }
      final got = await asMcp('get', {'profileId': id});
      a.check((got['revision'] as Map)['revision'] == 1);
      final update = {
        'requestId': requestId(),
        'profileId': id,
        'expectedRevision': 1,
        'body': catalogBody(),
      };
      a.check((await asMcp('update', update))['revision'] == 2);
      a.check((await asMcp('update', update))['revision'] == 2);
      await a.fails(asOwner('update', update), 'FORBIDDEN');
      final diff = await asMcp('compare', {
        'profileId': id,
        'fromRevision': 1,
        'toRevision': 2,
      });
      a.check(diff.isNotEmpty);
      a.check(
        (await asMcp('validate', {'body': catalogBody()}))['valid'] == true,
      );
      var malformedDenied = false;
      try {
        await asOwner('validate', {'body': {}});
      } on FormatException {
        malformedDenied = true;
      }
      a.check(malformedDenied);
      final invalidBody = {
        ...catalogBody(),
        'steps': [
          {
            'id': 'invalid_ref',
            'kind': 'config_file',
            'resourceId': 'system.motd',
            'values': {
              'text': {'param': 'missing'},
            },
          },
        ],
      };
      a.check(
        (await asOwner('validate', {'body': invalidBody}))['valid'] == false,
      );
      await asOwner('archive', {
        'requestId': requestId(),
        'profileId': id,
        'expectedRevision': 2,
      });
      a.check(
        ((await asMcp('get', {'profileId': id}))['profile']
                as Map)['archived'] ==
            true,
      );
      if (mode == 'close') {
        await catalog.close();
        await a.fails(asOwner('list', {}), 'NOT_READY');
      }
      a.check(store.isTrustedSnapshotLoaded);
    } finally {
      await _cleanup([
        () async => service?.close(),
        () async {
          if (expectGateCloseFailure) {
            await a.fails(sessions.close(), 'SERVICE_UNAVAILABLE');
          } else {
            await sessions.close();
          }
        },
        () async => mcp?.close(),
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
    stderr.writeln(
      'TRUSTED_CATALOG_FIXTURE_FAILED:$_stage:${error.runtimeType}',
    );
    exitCode = 1;
  }
}
