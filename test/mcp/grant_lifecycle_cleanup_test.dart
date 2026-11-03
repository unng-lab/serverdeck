import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/domain/models.dart';

import '../fixtures/feature_harness.dart';

void main() {
  late FeatureHarness h;
  setUp(() => h = FeatureHarness());
  tearDown(() => h.dispose());
  for (final phrase in [false, true]) {
    test(
      'expiry cancels ${phrase ? 'passphrase' : 'trust'} wait even after its pipe has EOF',
      () async {
        final grant = await h.grants.issue(h.actors.ui, 'A', confirmed: true);
        await h.grants.setEnabled(h.actors.ui, true);
        h.clock.advance(const Duration(days: 90) - const Duration(minutes: 4));
        String id;
        if (phrase) {
          final bytes = Uint8List.fromList(
            File('test/fixtures/ssh/ed25519-encrypted.txt').readAsBytesSync(),
          );
          final auth = PrivateKeyInput(
            bytes,
            passphrase: 'serverdeck-unit-passphrase',
          );
          bytes.fillRange(0, bytes.length, 0);
          final result = await h.profiles.createProfile(
            h.actors.ui,
            ProfileDraft(
              displayName: 'Encrypted',
              host: 'host.invalid',
              username: 'root',
              authentication: auth,
            ),
            mutationId: h.newId(),
          );
          expect(result.error, isNull);
          id = result.value!.entityId;
        } else {
          id = await h.create();
        }
        final actor = h.actors.mcp(clientId: grant.clientId, grantVersion: 1),
            session = await h.connect(id, actor: actor);
        session.askPassphrase = phrase;
        final authentication = session.authenticate();
        await featureTurns();
        if (phrase) {
          final challenge = (await h.trust.getTrust(
            h.actors.ui,
            id,
          )).value!.challenge!;
          expect(
            (await h.trust.acceptTrust(
              h.actors.ui,
              h.decision(id, challenge),
            )).ok,
            isTrue,
          );
          await featureTurns();
          expect(
            h.connections.connection(id).state,
            ConnectionState.needPassphrase,
          );
        } else {
          expect(h.connections.connection(id).state, ConnectionState.needTrust);
        }
        // A transport EOF closes its channel, not the already admitted domain call.
        await h.transport.closeClient(grant.clientId);
        expect(session.closed, isFalse);
        h.clock.advance(const Duration(minutes: 4));
        await featureTurns(40);
        await authentication;
        expect(session.closed, isTrue);
        expect(h.connections.connection(id).state, ConnectionState.cancelled);
        expect(h.connections.connection(id).pendingInput, isNull);
        expect(
          (await h.trust.getTrust(h.actors.ui, id)).value!.challenge,
          isNull,
        );
      },
    );
  }
  for (final held in [false, true]) {
    test(
      'disable starts B and listener cleanup despite ${held ? 'held' : 'failed'} A',
      () async {
        final a = await h.grants.issue(h.actors.ui, 'A', confirmed: true),
            b = await h.grants.issue(h.actors.ui, 'B', confirmed: true);
        await h.grants.setEnabled(h.actors.ui, true);
        final aid = await h.create(host: 'a.invalid'),
            bid = await h.create(host: 'b.invalid');
        final sa = await h.connect(
          aid,
          actor: h.actors.mcp(clientId: a.clientId, grantVersion: 1),
        );
        final aa = sa.authenticate();
        await featureTurns();
        final sb = await h.connect(
          bid,
          actor: h.actors.mcp(clientId: b.clientId, grantVersion: 1),
        );
        final ab = sb.authenticate();
        await featureTurns();
        if (held) {
          h.transport.heldClients[a.clientId] = Completer<void>();
        } else {
          h.transport.failedClients.add(a.clientId);
        }
        final disable = h.grants.setEnabled(h.actors.ui, false);
        final failed = expectLater(
          disable,
          throwsA(featureFailure(FailureCode.cleanupRequired)),
        );
        await featureTurns(40);
        expect(h.grants.enabled, isFalse);
        expect(h.transport.enabled, isFalse);
        expect(h.transport.closedClients, contains(b.clientId));
        expect(sa.closed, isTrue);
        expect(sb.closed, isTrue);
        await aa;
        await ab;
        if (held) {
          h.clock.advance(const Duration(seconds: 5));
        }
        await failed;
        expect(h.repository.state.grants[a.clientId]!.grantVersion, 1);
        expect(h.repository.state.grants[b.clientId]!.grantVersion, 1);
        h.transport.failedClients.clear();
        h.transport.heldClients[a.clientId]?.complete();
        await featureTurns();
        await h.grants.setEnabled(h.actors.ui, false);
        expect(h.transport.enabled, isFalse);
      },
    );
  }
}
