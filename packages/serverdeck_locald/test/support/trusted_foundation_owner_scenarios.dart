import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_locald/api/operational_auth.dart';
import 'package:serverdeck_locald/api/owner_api.dart';
import 'package:serverdeck_locald/api/trusted_owner_foundation.dart';
import 'package:serverdeck_locald/profiles/mutation_coordinator.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';

import 'trusted_auth_actor.dart' as a;

Future<void> exerciseTrustedFoundationOwner(
  String root,
  String mode,
  StateStore store,
  KeyCustody custody,
  ReceiptKeyMaterial key,
  a.Pair owner,
  TrustedSessions plain,
) async {
  final sessions = owner.registry;
  final coordinator = TrustedMutationCoordinator(store, custody, key);
  TrustedFoundationOwnerApi? adapter;
  a.Pair? other;
  var counter = 70000;
  String id() =>
      '62345678-1234-4234-8234-${(++counter).toString().padLeft(12, '0')}';
  const profile = '62345678-1234-4234-8234-000000070000';
  Map<String, Object?> settings() => {
    'expectedRevision': store.state.settings.revision,
    'theme': 'dark',
    'reduceMotion': true,
    'selectedProfileId': null,
  };
  Map<String, Object?> create() => {
    'profileId': profile,
    'name': 'Fixed foundation input',
    'address': 'foundation.invalid',
    'port': 22,
    'sshUser': 'fixture',
    'tags': <String>[],
    'credential': {'action': 'remove'},
  };
  Future<TrustedSessionRequest> request(String method) =>
      sessions.begin(owner.channel, owner.response!.sessionId, method);
  try {
    if (mode == 'foundation-gate') {
      await a.fails(
        Future.sync(
          () => TrustedFoundationOwnerApi(
            store: store,
            coordinator: coordinator,
            sessions: plain,
          ),
        ),
        'NOT_READY',
      );
      a.check(store.isTrustedSnapshotLoaded);
      return;
    }
    final api = adapter = TrustedFoundationOwnerApi(
      store: store,
      coordinator: coordinator,
      sessions: sessions,
    );
    Future<Map<String, Object?>> dispatch(
      String method,
      Map<String, Object?> body, {
      String? requestId,
    }) async {
      final interest = await request(method);
      try {
        return await api.dispatch(
          interest,
          method,
          body,
          requestId: requestId ?? id(),
        );
      } finally {
        interest.complete();
      }
    }

    if (mode == 'foundation-role' || mode == 'foundation-foreign') {
      final mcp = mode == 'foundation-role';
      final pair = other = await a.Pair.start(
        root,
        mcp ? 'mcp.exe' : 'serverdeck.exe',
        mcp ? sessions : plain,
      );
      await pair.exchange();
      a.check(await pair.next() == (mcp ? 'AUTH:mcp' : 'AUTH:owner'));
      final method = mcp ? 'session.ping' : 'settings.update';
      final interest = await (mcp ? sessions : plain).begin(
        pair.channel,
        pair.response!.sessionId,
        method,
      );
      try {
        await a.fails(
          Future.sync(
            () => api.prepare(interest, method, {
              'invalid': true,
            }, requestId: 'invalid'),
          ),
          'FORBIDDEN',
        );
      } finally {
        interest.complete();
      }
      return;
    }
    if (mode == 'foundation-admission' || mode == 'foundation-close') {
      final interest = sessions.reserve(
        owner.channel,
        owner.response!.sessionId,
        'settings.update',
      );
      final mutation = id(), input = settings();
      final prepared = api.prepare(
        interest,
        'settings.update',
        input,
        requestId: mutation,
      );
      try {
        a.check(coordinator.status(mutation).toJson()['state'] == 'queued');
        await a.fails(prepared.execute(), 'FORBIDDEN');
        a.check(store.state.settings.toJson()['theme'] != 'dark');
        input['theme'] = 'light';
        if (mode == 'foundation-close') {
          prepared.close();
          a.check(
            coordinator.status(mutation).toJson()['state'] == 'not-found',
          );
          await sessions.completeAdmission(interest);
          await a.fails(prepared.execute(), 'SERVICE_UNAVAILABLE');
          await api.close();
          await a.fails(
            Future.sync(
              () => api.prepare(
                interest,
                'settings.update',
                input,
                requestId: id(),
              ),
            ),
            'NOT_READY',
          );
        } else {
          await sessions.completeAdmission(interest);
          final work = prepared.execute();
          a.check(identical(work, prepared.execute()));
          await work;
          a.check(store.state.settings.toJson()['theme'] == 'dark');
        }
      } finally {
        prepared.close();
        interest.complete();
      }
      return;
    }
    if (mode == 'foundation-blocked' || mode == 'foundation-retired') {
      final gate = await owner.peer!.publicationGate(a.generation);
      final held = await gate.acquire();
      final interest = await request('profiles.create');
      final mutation = id(), input = create();
      final prepared = api.prepare(
        interest,
        'profiles.create',
        input,
        requestId: mutation,
      );
      final work = prepared.execute();
      work.ignore();
      try {
        input['address'] = 'changed-after-capture.invalid';
        (input['tags'] as List).add('changed');
        await Future<void>.delayed(const Duration(milliseconds: 40));
        a.check(!store.state.profiles.containsKey(profile));
        a.check(coordinator.status(mutation).toJson()['state'] == 'queued');
        if (mode == 'foundation-retired') interest.complete();
        await held.close();
        if (mode == 'foundation-retired') {
          await a.fails(work, 'UNAUTHORIZED');
          a.check(!store.state.profiles.containsKey(profile));
        } else {
          await work;
          a.check(
            store.state.profiles[profile]!.toJson()['address'] ==
                'foundation.invalid',
          );
          a.check(
            (store.state.profiles[profile]!.toJson()['tags'] as List).isEmpty,
          );
        }
      } finally {
        prepared.close();
        interest.complete();
        await held.close();
        await gate.close();
      }
      return;
    }
    a.check(mode == 'foundation-basic');
    final mcp = other = await a.Pair.start(root, 'mcp.exe', sessions);
    await mcp.exchange();
    a.check(await mcp.next() == 'AUTH:mcp');
    final mutation = id(), input = settings();
    final saved = await dispatch('settings.update', input, requestId: mutation);
    a.check(
      jsonEncode(
            await dispatch('settings.update', input, requestId: mutation),
          ) ==
          jsonEncode(saved),
    );
    final ping = await sessions.begin(
      mcp.channel,
      mcp.response!.sessionId,
      'session.ping',
    );
    ping.complete();
    await a.fails(
      dispatch('settings.update', {
        ...input,
        'theme': 'light',
      }, requestId: mutation),
      'IDEMPOTENCY_CONFLICT',
    );
    a.check(
      (await dispatch('mutations.get', {'requestId': mutation}))['state'] ==
          'committed',
    );
    final created = await dispatch('profiles.create', create());
    a.check(created['entityRevision'] == '1');
    await a.fails(
      sessions.begin(mcp.channel, mcp.response!.sessionId, 'session.ping'),
      'UNAUTHORIZED',
    );
    a.check((await dispatch('profiles.list', {}))['profiles'] is List);
    final fetched = await dispatch('profiles.get', {'profileId': profile});
    a.check((fetched['profile'] as Map)['trustRevision'] == '1');
    a.check((await dispatch('settings.get', {}))['settings'] is Map);
    await dispatch('profiles.update', {
      ...create(),
      'expectedRevision': '1',
      'address': 'changed.invalid',
      'credential': {'action': 'keep'},
    });
    final changed = store.state.profiles[profile]!;
    a.check(changed.connectionRevision == '2' && changed.trustRevision == '2');
    await dispatch('profiles.delete', {
      'profileId': profile,
      'expectedRevision': '2',
    });
    a.check(!store.state.profiles.containsKey(profile));
    a.check((await dispatch('mutations.recent', {}))['receipts'] is List);
    final unsupported = await request('session.ping');
    try {
      await a.fails(
        Future.sync(
          () => api.prepare(unsupported, 'session.ping', {}, requestId: id()),
        ),
        'UNSUPPORTED',
      );
      await a.fails(
        Future.sync(
          () => api.prepare(unsupported, 'settings.get', {}, requestId: id()),
        ),
        'FORBIDDEN',
      );
    } finally {
      unsupported.complete();
    }
  } finally {
    try {
      await adapter?.close();
    } finally {
      try {
        await coordinator.close();
      } finally {
        await other?.close();
      }
    }
  }
}
