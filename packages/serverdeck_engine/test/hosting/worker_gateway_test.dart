import 'dart:async';

import 'package:serverdeck_engine/hosting/in_process_gateway.dart';
import 'package:test/test.dart';

import 'in_process_gateway_test.dart' as core;
import 'sessions_test.dart' show settle;

Object? copyMessage(Object? value) => switch (value) {
  List<int>() => List<int>.of(value),
  Map<String, Object?>() => value.map((k, v) => MapEntry(k, copyMessage(v))),
  List() => value.map(copyMessage).toList(),
  _ => value,
};

final class ClockTimers {
  ClockTimers(this.setup);
  final core.Setup setup;
  final timers =
      <({Duration at, void Function() action, bool Function() active})>[];
  void Function() schedule(Duration delay, void Function() action) {
    var active = true;
    timers.add((
      at: setup.auth.elapsed + delay,
      action: action,
      active: () => active,
    ));
    return () => active = false;
  }

  void advance(Duration duration) {
    setup.auth.elapsed += duration;
    for (final timer in timers.toList()) {
      if (timer.active() && timer.at <= setup.auth.elapsed) timer.action();
    }
  }
}

// Mirrors SendPort snapshot semantics in RAM; no isolate/native process starts.
final class Channel implements GatewayChannel {
  final stream = StreamController<Object?>(sync: true);
  GatewayWorkerBinding? worker;
  bool disposed = false,
      queued = false,
      holdSettled = false,
      failAfterPost = false;
  bool failReplyAfterPost = false;
  bool deferReplies = false;
  final replies = <Map<String, Object?>>[];
  final replyKinds = <Object?>[];
  final queue = <Map<String, Object?>>[],
      settlements = <Map<String, Object?>>[];
  final calls = <Map<String, Object?>>[];
  final sentBodies = <List<int>>[], receivedBodies = <List<int>>[];
  @override
  Stream<Object?> get messages => stream.stream;
  @override
  void send(Map<String, Object?> frame) {
    if (disposed) throw StateError('private transport');
    if (frame['body'] is List<int>) sentBodies.add(frame['body'] as List<int>);
    final snapshot = copyMessage(frame) as Map<String, Object?>;
    if (frame['kind'] == 'call')
      calls.add(copyMessage(frame) as Map<String, Object?>);
    if (queued)
      queue.add(snapshot);
    else
      worker!.handle(snapshot);
    if (failAfterPost) throw StateError('uncertain private delivery');
  }

  void reply(Map<String, Object?> frame) {
    if (disposed) throw StateError('private receiver gone');
    replyKinds.add(frame['kind']);
    if (frame['body'] is List<int>)
      receivedBodies.add(frame['body'] as List<int>);
    final snapshot = copyMessage(frame) as Map<String, Object?>;
    if (deferReplies)
      replies.add(snapshot);
    else if (holdSettled && frame['kind'] == 'settled')
      settlements.add(snapshot);
    else
      stream.add(snapshot);
    if (failReplyAfterPost && frame['kind'] == 'result')
      throw StateError('uncertain reply delivery');
  }

  void flush() {
    final pending = queue.toList();
    queue.clear();
    for (final frame in pending) worker!.handle(frame);
  }

  void releaseSettled() {
    final pending = settlements.toList();
    settlements.clear();
    for (final frame in pending) stream.add(frame);
  }

  void releaseReplies() {
    final pending = replies.toList();
    replies.clear();
    for (final frame in pending) stream.add(frame);
  }

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    stream.close().ignore();
  }
}

final class Bridge {
  Bridge(this.setup) : timers = ClockTimers(setup) {
    server = GatewayWorkerBinding(
      gateway: setup.gateway,
      send: channel.reply,
      detach: setup.gateway.close,
    );
    channel.worker = server;
    proxy = WorkerGatewayProxy(
      generation: setup.owner.generation,
      channel: channel,
      nowMicros: () => setup.auth.elapsed.inMicroseconds,
      schedule: timers.schedule,
    );
  }
  final core.Setup setup;
  final ClockTimers timers;
  final channel = Channel();
  late final GatewayWorkerBinding server;
  late final WorkerGatewayProxy proxy;
  static Future<Bridge> create() async => Bridge(await core.Setup.create());
  Future<Map<String, Object?>> call([Map<String, Object?> params = const {}]) =>
      proxy.call('settings.get', params, requestId: core.id);
  Future<void> close() async {
    await proxy.close();
    await server.close();
    await setup.auth.close();
  }

  Future<void> failedClose() async {
    await expectLater(proxy.close(), core.failure('SERVICE_UNAVAILABLE'));
    await expectLater(server.close(), core.failure('SERVICE_UNAVAILABLE'));
    await setup.auth.close();
  }
}

// A callback already handed to a listener may be in flight at cancellation.
// Capturing it lets a RAM test exercise that discard path without test hooks.
final class InFlightStream extends Stream<Object?> {
  final backing = StreamController<Object?>();
  late void Function(Object?) deliver;
  @override
  StreamSubscription<Object?> listen(
    void Function(Object?)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    deliver = onData!;
    return backing.stream.listen(
      (_) {},
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }
}

final class InFlightChannel implements GatewayChannel {
  final stream = InFlightStream();
  bool disposed = false;
  @override
  Stream<Object?> get messages => stream;
  @override
  void send(Map<String, Object?> frame) {}
  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    stream.backing.close().ignore();
  }
}

void main() {
  test(
    'retired worker binding wipes late mutable input without another operation',
    () async {
      final b = await Bridge.create();
      await b.close();
      final closing = b.server.close(),
          body = <int>[112, 114, 105, 118, 97, 116, 101];
      b.server.handle({
        'kind': 'call',
        'generation': b.proxy.generation,
        'sequence': 1,
        'id': core.id,
        'method': 'settings.get',
        'expiresAt': 5000000,
        'body': body,
      });
      expect(body.every((byte) => byte == 0), isTrue);
      expect(b.setup.services.prepared, 0);
      expect(b.setup.services.effects, 0);
      expect(identical(closing, b.server.close()), isTrue);
      await closing;
    },
  );

  test(
    'retired proxy wipes an already-dispatched callback after cancellation',
    () async {
      final channel = InFlightChannel();
      final proxy = WorkerGatewayProxy(
        generation: core.workspace,
        channel: channel,
      );
      channel.stream.deliver({'kind': 'result', 'generation': 'foreign'});
      await expectLater(proxy.close(), core.failure('SERVICE_UNAVAILABLE'));
      final body = <int>[112, 114, 105, 118, 97, 116, 101];
      channel.stream.deliver({'body': body});
      expect(body.every((byte) => byte == 0), isTrue);
      expect(proxy.isClosed, isTrue);
    },
  );

  test(
    'bound proxy captures input, freezes output and wipes transport buffers',
    () async {
      final b = await Bridge.create();
      Map<String, Object?>? captured;
      b.setup.services.onPrepare = (_, params) => captured = params;
      final output = <String, Object?>{
        'text': 'e\u0301',
        'ratio': 1.25,
        'items': [1, 2],
      };
      b.setup.services.effect = (_, __) async => output;
      final params = <String, Object?>{
        'value': [1, 2],
      };
      final pending = b.call(params);
      (params['value'] as List)[0] = 99;
      final result = await pending;
      output['text'] = 'changed';
      expect(captured!['value'], [1, 2]);
      expect(result['text'], 'e\u0301');
      expect(() => (result['items'] as List).add(3), throwsUnsupportedError);
      await settle();
      expect(b.proxy.pendingRequests, 0);
      expect(
        b.channel.sentBodies.every((bytes) => bytes.every((v) => v == 0)),
        isTrue,
      );
      expect(
        b.channel.receivedBodies.every((bytes) => bytes.every((v) => v == 0)),
        isTrue,
      );
      expect(b.channel.calls.single.keys, isNot(contains('role')));
      expect(b.channel.calls.single.keys, isNot(contains('sessionId')));
      await b.close();
    },
  );

  test('a completed reply keeps its token until actual worker settlement acknowledgement', () async {
    final b = await Bridge.create();
    b.channel.holdSettled = true;
    await Future.wait([for (var i = 0; i < 16; i++) b.call()]);
    await settle();
    expect(b.proxy.pendingRequests, 16);
    await expectLater(b.call(), core.failure('RESOURCE_LIMIT'));
    expect(b.channel.calls, hasLength(16));
    b.channel.holdSettled = false;
    b.channel.releaseSettled();
    expect(b.proxy.pendingRequests, 0);
    await b.call();
    await b.close();
  });

  test(
    'queued expired command gets no new five-second admission or effect',
    () async {
      final b = await Bridge.create();
      b.channel.queued = true;
      final pending = b.call();
      b.timers.advance(const Duration(seconds: 6));
      await expectLater(pending, core.failure('TIMEOUT'));
      expect(b.proxy.pendingRequests, 1);
      b.channel.queued = false;
      b.channel.flush();
      await settle();
      expect(b.setup.services.prepared, 0);
      expect(b.setup.services.effects, 0);
      expect(b.proxy.pendingRequests, 0);
      await b.close();
    },
  );

  test('queue residence consumes the exact original absolute budget', () async {
    final b = await Bridge.create();
    b.channel.queued = true;
    Duration? remaining;
    b.setup.services.onPrepare = (request, _) =>
        remaining = request.rpcBudgetRemaining;
    final pending = b.call();
    b.timers.advance(const Duration(seconds: 4));
    b.channel.queued = false;
    b.channel.flush();
    await pending;
    expect(remaining, const Duration(seconds: 1));
    expect(b.channel.calls.single['expiresAt'], 5000000);
    await b.close();
  });

  test(
    'caller timeout leaves accepted physical effect charged without replay',
    () async {
      final b = await Bridge.create(),
          effect = Completer<Map<String, Object?>>();
      b.setup.services.effect = (_, __) => effect.future;
      final pending = b.call();
      await settle();
      expect(b.setup.services.effects, 1);
      b.timers.advance(const Duration(seconds: 6));
      await expectLater(pending, core.failure('TIMEOUT'));
      expect(b.proxy.pendingRequests, 1);
      effect.complete(core.settings());
      await settle();
      expect(b.proxy.pendingRequests, 0);
      expect(b.setup.services.effects, 1);
      await b.close();
    },
  );

  test(
    'reserved close stops interest now and waits already accepted work',
    () async {
      final b = await Bridge.create(),
          effect = Completer<Map<String, Object?>>();
      b.setup.services.effect = (_, __) => effect.future;
      final pending = b.call();
      await settle();
      final closing = b.proxy.close();
      expect(identical(closing, b.proxy.close()), isTrue);
      await expectLater(pending, core.failure('SERVICE_UNAVAILABLE'));
      await expectLater(b.call(), core.failure('SERVICE_UNAVAILABLE'));
      var closed = false;
      closing.then((_) => closed = true).ignore();
      await settle();
      expect(closed, isFalse);
      expect(b.proxy.pendingRequests, 1);
      effect.complete(core.settings());
      await closing;
      expect(b.proxy.pendingRequests, 0);
      await b.close();
    },
  );

  test('reentrant close during prepare retains cleanup failure and issues no effect', () async {
    final b = await Bridge.create();
    b.setup.services.failClose = true;
    b.setup.services.onPrepare = (_, __) {
      b.proxy.close().ignore();
    };
    await expectLater(b.call(), core.failure('SERVICE_UNAVAILABLE'));
    await settle();
    expect(b.setup.services.effects, 0);
    await b.failedClose();
  });

  test(
    'wrong-generation reply retires channel without proving physical release',
    () async {
      final b = await Bridge.create(),
          effect = Completer<Map<String, Object?>>();
      b.setup.services.effect = (_, __) => effect.future;
      final pending = b.call();
      await settle();
      b.channel.reply({
        'kind': 'settled',
        'generation': core.workspace,
        'sequence': 1,
        'id': core.id,
        'ok': true,
      });
      await expectLater(pending, core.failure('SERVICE_UNAVAILABLE'));
      expect(b.proxy.isClosed, isTrue);
      expect(b.proxy.pendingRequests, 1);
      effect.complete(core.settings());
      await settle();
      await b.failedClose();
    },
  );

  test(
    'unknown role/control fields cannot create another owner route',
    () async {
      final b = await Bridge.create();
      b.server.handle({
        'kind': 'call',
        'generation': b.proxy.generation,
        'sequence': 1,
        'id': core.id,
        'method': 'settings.get',
        'expiresAt': 5000000,
        'body': <int>[123, 125],
        'role': 'owner',
      });
      await settle();
      expect(b.setup.services.prepared, 0);
      await b.failedClose();
    },
  );

  test(
    'session.close has a narrow terminal reply and retires its proxy',
    () async {
      final b = await Bridge.create();
      expect(await b.proxy.call('session.close', {}, requestId: core.id), {
        'closed': true,
      });
      await settle();
      expect(b.proxy.isClosed, isTrue);
      await expectLater(b.call(), core.failure('SERVICE_UNAVAILABLE'));
      await b.close();
    },
  );

  test(
    'uncertain post is never replayed and never returns its token',
    () async {
      final b = await Bridge.create(),
          effect = Completer<Map<String, Object?>>();
      b.setup.services.effect = (_, __) => effect.future;
      b.channel.failAfterPost = true;
      await expectLater(b.call(), core.failure('SERVICE_UNAVAILABLE'));
      await settle();
      expect(b.setup.services.effects, lessThanOrEqualTo(1));
      expect(b.channel.calls, hasLength(1));
      expect(b.proxy.pendingRequests, 1);
      effect.complete(core.settings());
      await settle();
      await b.failedClose();
    },
  );

  test('beginCall distinguishes response timeout from native-proof physical completion', () async {
    final s = await core.Setup.create(), pause = Completer<void>();
    s.auth.runtime.paused = pause;
    final invocation = s.gateway.beginCall(
      'settings.get',
      {},
      requestId: core.id,
      expiresAt: const Duration(milliseconds: 10),
    );
    var settled = false;
    invocation.settled.then((_) => settled = true).ignore();
    await expectLater(invocation.result, core.failure('TIMEOUT'));
    expect(settled, isFalse);
    expect(s.services.effects, 0);
    final close = s.gateway.close();
    pause.complete();
    await invocation.settled;
    await close;
    expect(settled, isTrue);
    await s.auth.close();
  });

  test(
    'uncertain worker reply is never resent as a second error/result',
    () async {
      final b = await Bridge.create();
      b.channel.failReplyAfterPost = true;
      expect(await b.call(), core.settings());
      await settle();
      expect(
        b.channel.replyKinds.where((kind) => kind == 'result'),
        hasLength(1),
      );
      expect(b.channel.replyKinds, isNot(contains('error')));
      expect(b.proxy.pendingRequests, 1);
      expect(b.setup.services.effects, 1);
      await b.failedClose();
    },
  );

  test(
    'delayed UI timer cannot publish a reply beyond its original deadline',
    () async {
      final b = await Bridge.create();
      b.channel.deferReplies = true;
      final pending = b.call();
      await settle();
      b.setup.auth.elapsed = const Duration(
        seconds: 6,
      ); // Timer delivery is still queued.
      b.channel.deferReplies = false;
      b.channel.releaseReplies();
      await expectLater(pending, core.failure('TIMEOUT'));
      expect(b.proxy.pendingRequests, 0);
      await b.close();
    },
  );

  test(
    'absolute expiry cannot enlarge RPC budget or reach typed preparation',
    () async {
      final s = await core.Setup.create();
      final invocation = s.gateway.beginCall(
        'settings.get',
        {},
        requestId: core.id,
        expiresAt: const Duration(seconds: 6),
      );
      await expectLater(invocation.result, core.failure('VALIDATION'));
      await invocation.settled;
      expect(s.services.prepared, 0);
      await s.close();
    },
  );
}
