import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/bootstrap/local_api_client.dart';
import 'package:serverdeck/profiles/mutation_controller.dart';
import 'package:serverdeck/profiles/profile_controller.dart';
import 'package:serverdeck_protocol/models.dart';

import 'profile_controller_test.dart';

Map<String, Object?> receipt(String revision) => {
  'entityId': null,
  'entityRevision': revision,
  'storeRevision': revision,
  'deleted': false,
};

class MutationClient extends ModelClient {
  final sent = <MutationIntent>[];
  final queried = <MutationIntent>[];
  Future<ApiReply> Function()? send;
  Future<ApiReply> Function()? status;
  @override
  Future<ApiReply> mutate(MutationIntent intent) {
    sent.add(intent);
    return send!();
  }

  @override
  Future<ApiReply> mutationStatus(MutationIntent intent) {
    queried.add(intent);
    return status!();
  }
}

void main() {
  late MutationClient client;
  late ModelBootstrap bootstrap;
  late ProfileController model;
  late MutationController controller;
  setUp(() {
    client = MutationClient();
    bootstrap = ModelBootstrap(client)..show(ReadinessState.ready);
    model = ProfileController(bootstrap: bootstrap);
    client.events.add(snapshot());
    controller = MutationController(model: model);
  });
  tearDown(() async {
    controller.dispose();
    model.dispose();
    bootstrap.dispose();
    await client.events.close();
    await client.readErrors.close();
    await client.close();
  });

  Future<void> submit() => controller.submit(ApiMethod.settingsUpdate, {
    'expectedRevision': '1',
    'theme': 'light',
    'reduceMotion': false,
    'selectedProfileId': null,
  });

  test(
    'commit waits for coherent current snapshot without applying receipt',
    () async {
      client.send = () async => ApiReply(fixtureGeneration, receipt('2'));
      await submit();
      expect(controller.state, MutationPresentation.committed);
      expect(model.storeRevision, '1');
      client.events.add(snapshot(revision: '2'));
      expect(controller.state, MutationPresentation.succeeded);
    },
  );

  test(
    'lost reply and status retain intent; retry is explicit and identical',
    () async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      await submit();
      final original = client.sent.single;
      expect(controller.state, MutationPresentation.unknown);
      await controller.retry();
      expect(client.sent, hasLength(1));
      for (final state in ['queued', 'running', 'not-found']) {
        client.status = () async =>
            ApiReply(fixtureGeneration, {'state': state, 'result': null});
        await controller.checkResult();
        expect(identical(client.queried.last, original), isTrue);
        expect(client.sent, hasLength(1));
      }
      expect(controller.state, MutationPresentation.retryAllowed);
      client.send = () async => ApiReply(fixtureGeneration, receipt('2'));
      await controller.retry();
      expect(identical(client.sent.last, original), isTrue);
      expect(controller.state, MutationPresentation.committed);
    },
  );

  test(
    'committed status rereads; lost readiness invalidates retry permission',
    () async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.serviceUnavailable);
      await submit();
      client.status = () async =>
          ApiReply(fixtureGeneration, {'state': 'not-found', 'result': null});
      await controller.checkResult();
      bootstrap.show(ReadinessState.unavailable);
      bootstrap.show(ReadinessState.ready);
      await controller.retry();
      expect(client.sent, hasLength(1));
      client.status = () async => ApiReply(fixtureGeneration, {
        'state': 'committed',
        'result': receipt('2'),
      });
      await controller.checkResult();
      expect(controller.state, MutationPresentation.committed);
      client.events.add(snapshot(revision: '3'));
      expect(controller.state, MutationPresentation.succeeded);
    },
  );

  test(
    'CAS error preserves request and requires explicit draft choice',
    () async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.revisionConflict);
      await submit();
      expect(controller.state, MutationPresentation.conflict);
      expect(controller.requestId, client.sent.single.id);
      await controller.retry();
      expect(client.sent, hasLength(1));
      controller.reset();
      expect(controller.state, MutationPresentation.idle);
    },
  );

  test(
    'late status from retired ready generation cannot authorize retry',
    () async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      await submit();
      final gate = Completer<ApiReply>();
      client.status = () => gate.future;
      final pending = controller.checkResult();
      bootstrap.show(ReadinessState.unavailable);
      bootstrap.show(ReadinessState.ready);
      gate.complete(
        ApiReply(fixtureGeneration, {'state': 'not-found', 'result': null}),
      );
      await pending;
      expect(controller.state, MutationPresentation.unknown);
      await controller.retry();
      expect(client.sent, hasLength(1));
    },
  );

  test(
    'dispose during notification prevents send and late completion',
    () async {
      client.send = () async => ApiReply(fixtureGeneration, receipt('2'));
      controller.addListener(controller.dispose);
      await submit();
      expect(client.sent, isEmpty);
    },
  );

  test('pending action cannot be submitted or reset twice', () async {
    final gate = Completer<ApiReply>();
    client.send = () => gate.future;
    final pending = submit();
    final id = controller.requestId;
    await submit();
    await controller.checkResult();
    controller.reset();
    expect(client.sent, hasLength(1));
    expect(client.queried, isEmpty);
    expect(controller.requestId, id);
    controller.dispose();
    gate.complete(ApiReply(fixtureGeneration, receipt('2')));
    await pending;
    expect(controller.requestId, isNull);
  });

  for (final reconnect in [false, true]) {
    for (final operation in ['submit', 'retry', 'status']) {
      test(
        'readiness revoked inline before $operation reconnect=$reconnect',
        () async {
          client.send = () async =>
              throw const LocalApiException(ErrorCode.timeout);
          if (operation != 'submit') await submit();
          if (operation == 'retry') {
            client.status = () async => ApiReply(fixtureGeneration, {
              'state': 'not-found',
              'result': null,
            });
            await controller.checkResult();
          }
          final sends = client.sent.length;
          final queries = client.queried.length;
          var revoked = false;
          controller.addListener(() {
            if (revoked || !controller.busy) return;
            revoked = true;
            bootstrap.show(ReadinessState.unavailable);
            if (reconnect) bootstrap.show(ReadinessState.ready);
          });
          if (operation == 'submit') {
            await submit();
          } else if (operation == 'retry') {
            await controller.retry();
          } else {
            client.status = () async => ApiReply(fixtureGeneration, {
              'state': 'not-found',
              'result': null,
            });
            await controller.checkResult();
          }
          expect(revoked, isTrue);
          expect(client.sent, hasLength(sends));
          expect(client.queried, hasLength(queries));
          expect(controller.state, MutationPresentation.unknown);
          expect(controller.busy, isFalse);
          expect(controller.requestId, isNotNull);
        },
      );
    }
  }

  test(
    'read failure after commit never permits resending known effect',
    () async {
      client.send = () async => ApiReply(fixtureGeneration, receipt('2'));
      await submit();
      client.readErrors.add(ErrorCode.timeout);
      await controller.retry();
      await controller.checkResult();
      expect(client.sent, hasLength(1));
      expect(client.queried, isEmpty);
      expect(controller.state, MutationPresentation.committed);
      client.events.add(snapshot(revision: '1'));
      expect(controller.state, MutationPresentation.committed);
      await controller.refreshCommitted();
      client.events.add(snapshot(revision: '2'));
      expect(controller.state, MutationPresentation.succeeded);
    },
  );

  test(
    'malformed receipt and arbitrary exception remain safely unknown',
    () async {
      client.send = () async =>
          ApiReply(fixtureGeneration, {'private': 'secret'});
      await submit();
      expect(controller.state, MutationPresentation.unknown);
      expect(controller.error, ErrorCode.internal);
      client.status = () async => throw StateError('private token/path');
      await controller.checkResult();
      expect(controller.state, MutationPresentation.unknown);
      expect(controller.error, ErrorCode.internal);
      expect(controller.error.toString(), isNot(contains('private')));
    },
  );

  test(
    'no-effect validation allows a new explicit action after reset',
    () async {
      client.send = () async =>
          throw const LocalApiException(ErrorCode.validation);
      await submit();
      final original = controller.requestId;
      expect(controller.state, MutationPresentation.failed);
      controller.reset();
      await submit();
      expect(controller.requestId, isNot(original));
    },
  );

  for (final operation in ['submit', 'retry', 'status', 'retry-reconnect']) {
    test('model listener before mutation listener $operation', () async {
      controller.dispose();
      var revoked = false;
      Future<void>? operationFuture;
      model.addListener(() {
        if (revoked || bootstrap.state != ReadinessState.unavailable) return;
        revoked = true;
        if (operation == 'retry-reconnect')
          bootstrap.show(ReadinessState.ready);
        operationFuture = switch (operation) {
          'submit' => submit(),
          'retry' || 'retry-reconnect' => controller.retry(),
          _ => controller.checkResult(),
        };
      });
      controller = MutationController(model: model);
      client.send = () async =>
          throw const LocalApiException(ErrorCode.timeout);
      client.status = () async =>
          ApiReply(fixtureGeneration, {'state': 'not-found', 'result': null});
      if (operation != 'submit') await submit();
      if (operation.startsWith('retry')) await controller.checkResult();
      final sends = client.sent.length;
      final queries = client.queried.length;
      bootstrap.show(ReadinessState.unavailable);
      await operationFuture;
      expect(revoked, isTrue);
      expect(client.sent, hasLength(sends));
      expect(client.queried, hasLength(queries));
      expect(controller.busy, isFalse);
      if (operation != 'submit') expect(controller.requestId, isNotNull);
    });
  }
}
