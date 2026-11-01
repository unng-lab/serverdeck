import 'dart:async';

import 'package:serverdeck_engine/hosting/authority.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

const generation = '12345678-1234-4234-9234-123456789abc';
const owner = 'S-1-5-21-1-2-3-1001';
Matcher failure(String code) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

final class Lease implements WorkspaceLease {
  @override
  String ownerIdentity = owner;
  @override
  String workspaceSlot = 'default';
  @override
  String get name => 'unit-owned-workspace';
  @override
  bool isHeld = true;
  @override
  bool acquired = true;
  int closes = 0;
  @override
  Future<void> close() async {
    closes++;
    isHeld = false;
  }
}

final class Gate implements PublicationGate {
  @override
  String generation = '12345678-1234-4234-9234-123456789abc';
  @override
  bool isClosed = false;
  @override
  int get activeAcquisitions => 0;
  @override
  int get activeLeases => 0;
  int closes = 0;
  Completer<void>? closing;
  @override
  PublicationAcquisition beginAcquire({
    Duration deadline = const Duration(seconds: 5),
  }) => throw StateError('UNSUPPORTED');
  @override
  Future<PublicationLease> acquire({
    Duration deadline = const Duration(seconds: 5),
  }) => throw StateError('UNSUPPORTED');
  @override
  Future<void> close() {
    closes++;
    isClosed = true;
    return closing?.future ?? Future.value();
  }
}

final class Runtime implements VerifiedRuntime {
  @override
  String ownerIdentity = owner;
  @override
  String appRoot = '/unit/app';
  @override
  String buildId = '${'a' * 40}+Release+${'b' * 64}';
  int proofs = 0, openings = 0;
  Object? proofError;
  void Function()? onProof;
  Completer<void>? paused;
  Completer<PublicationGate>? opening;
  final gate = Gate();
  @override
  Future<void> revalidate(WorkspaceLease lease) async {
    proofs++;
    onProof?.call();
    final error = proofError;
    if (error != null) throw error;
    await paused?.future;
  }

  @override
  Future<PublicationGate> createPublicationGate(
    String generation,
    WorkspaceLease lease,
  ) {
    openings++;
    return opening?.future ?? Future.value(gate);
  }
}

final class ManualClock implements EngineClock {
  @override
  Duration elapsed = Duration.zero;
  @override
  DateTime get utcNow => DateTime.utc(2026).add(elapsed);
}

HostAuthority prepare(Runtime runtime, Lease lease) => HostAuthority.prepare(
  runtime: runtime,
  lease: lease,
  generation: generation,
);
Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('observed writer loss revokes all owners without releasing cleanup ownership', () async {
    final runtime = Runtime(), lease = Lease();
    final authority = prepare(runtime, lease);
    await authority.initialize();
    final first = await authority.bindOwner(Object()),
        second = await authority.bindOwner(Object());
    lease.isHeld =
        false; // The platform has observed worker exit, not close ACK.
    await expectLater(authority.validateOwner(first), failure('UNAUTHORIZED'));
    expect(authority.isStopping, isTrue);
    expect(first.isRevoked, isTrue);
    expect(second.isRevoked, isTrue);
    expect(runtime.gate.isClosed, isTrue);
    expect(() => authority.bindOwner(Object()), failure('SERVICE_UNAVAILABLE'));
    await authority.close();
    expect(
      lease.closes,
      0,
    ); // Only the resource owner may await/release the lease.
  });
  for (final seconds in [5, 6]) {
    test(
      'owner issuance refuses a successful proof at elapsed ${seconds}s',
      () async {
        final runtime = Runtime(), lease = Lease(), clock = ManualClock();
        final authority = HostAuthority.prepare(
          runtime: runtime,
          lease: lease,
          generation: generation,
          clock: clock,
        );
        await authority.initialize();
        final existing = await authority.bindOwner(Object());
        runtime.onProof = () => clock.elapsed += Duration(seconds: seconds);
        final window = Object();
        await expectLater(authority.bindOwner(window), failure('TIMEOUT'));
        expect(authority.ownerCount, 1);
        expect(authority.pendingProofs, 0);
        expect(authority.isStopping, isFalse);
        runtime.onProof = null;
        await authority.validateOwner(existing);
        final replacement = await authority.bindOwner(window);
        expect(replacement.isRevoked, isFalse);
        expect(authority.ownerCount, 2);
        await authority.close();
        expect(lease.closes, 0);
      },
    );
  }

  test(
    'owner issuance requires actual completed runtime and publication checks',
    () async {
      final runtime = Runtime(), lease = Lease();
      final authority = prepare(runtime, lease);
      expect(() => authority.bindOwner(Object()), failure('NOT_READY'));
      await authority.initialize();
      expect(runtime.proofs, 2);
      expect(identical(authority.publicationGate, runtime.gate), isTrue);
      final ui = Object();
      final capability = await authority.bindOwner(ui);
      expect(capability.generation, generation);
      expect(capability.isRevoked, isFalse);
      expect(identical(await authority.bindOwner(ui), capability), isTrue);
      expect(authority.ownerCount, 1);
      final closing = authority.close();
      expect(identical(closing, authority.close()), isTrue);
      expect(capability.isRevoked, isTrue);
      expect(() => authority.bindOwner(ui), failure('SERVICE_UNAVAILABLE'));
      await closing;
      expect(runtime.gate.closes, 1);
      expect(lease.closes, 0); // Authority cannot establish store closure.
    },
  );

  test('foreign and revoked owner objects never become authority from matching IDs', () async {
    final first = prepare(Runtime(), Lease()),
        second = prepare(Runtime(), Lease());
    await Future.wait([first.initialize(), second.initialize()]);
    final a = await first.bindOwner(Object()),
        b = await second.bindOwner(Object());
    await expectLater(second.validateOwner(a), failure('UNAUTHORIZED'));
    expect(second.isStopping, isFalse);
    await second.validateOwner(b);
    first.revokeOwner(a);
    await expectLater(first.validateOwner(a), failure('UNAUTHORIZED'));
    expect(b.isRevoked, isFalse);
    await Future.wait([first.close(), second.close()]);
  });

  test('eight pending windows reserve quota and duplicate opens join the same work', () async {
    final runtime = Runtime();
    final authority = prepare(runtime, Lease());
    await authority.initialize();
    final pause = runtime.paused = Completer<void>();
    final windows = List.generate(8, (_) => Object());
    final pending = [for (final window in windows) authority.bindOwner(window)];
    expect(
      identical(authority.bindOwner(windows.first), pending.first),
      isTrue,
    );
    expect(() => authority.bindOwner(Object()), failure('RESOURCE_LIMIT'));
    expect(authority.pendingProofs, 8);
    pause.complete();
    final capabilities = await Future.wait(pending);
    expect(capabilities.map((value) => value.sessionId).toSet(), hasLength(8));
    expect(authority.ownerCount, 8);
    await authority.close();
  });

  test('window detach during proof does not revive an owner or retire its replacement', () async {
    final runtime = Runtime(), lease = Lease();
    final authority = prepare(runtime, lease);
    await authority.initialize();
    final ui = Object(), pause = runtime.paused = Completer<void>();
    final old = authority.bindOwner(ui);
    final denied = expectLater(old, failure('UNAUTHORIZED'));
    authority.detachOwner(ui);
    runtime.paused = null;
    final replacement = await authority.bindOwner(ui);
    pause.complete();
    await denied;
    await settle();
    expect(authority.ownerCount, 1);
    expect(replacement.isRevoked, isFalse);
    await authority.validateOwner(replacement);
    await authority.close();
  });

  test(
    'local revocation while validating one owner leaves other windows usable',
    () async {
      final runtime = Runtime();
      final authority = prepare(runtime, Lease());
      await authority.initialize();
      final a = await authority.bindOwner(Object()),
          b = await authority.bindOwner(Object());
      final pause = runtime.paused = Completer<void>();
      final validating = authority.validateOwner(a);
      final denied = expectLater(validating, failure('UNAUTHORIZED'));
      authority.revokeOwner(a);
      runtime.paused = null;
      pause.complete();
      await denied;
      expect(authority.isStopping, isFalse);
      await authority.validateOwner(b);
      await authority.close();
    },
  );

  test('logical proof timeout retains physical work and cannot restore a capability', () async {
    final runtime = Runtime(), lease = Lease();
    final authority = prepare(runtime, lease);
    await authority.initialize();
    final cap = await authority.bindOwner(Object());
    final pause = runtime.paused = Completer<void>();
    await expectLater(
      authority.validateOwner(cap, deadline: const Duration(milliseconds: 10)),
      failure('TIMEOUT'),
    );
    expect(cap.isRevoked, isTrue);
    expect(authority.pendingProofs, 1);
    var closed = false;
    final closing = authority.close().then((_) => closed = true);
    await settle();
    expect(closed, isFalse);
    expect(lease.closes, 0);
    pause.complete();
    await closing;
    expect(authority.pendingProofs, 0);
    expect(cap.isRevoked, isTrue);
  });

  test(
    'late publication gate after shutdown is closed before settlement',
    () async {
      final runtime = Runtime(), lease = Lease();
      runtime.opening = Completer<PublicationGate>();
      runtime.gate.closing = Completer<void>();
      final authority = prepare(runtime, lease);
      final starting = authority.initialize();
      final denied = expectLater(starting, failure('SERVICE_UNAVAILABLE'));
      await settle();
      expect(runtime.openings, 1);
      var closed = false;
      final closing = authority.close().then((_) => closed = true);
      runtime.opening!.complete(runtime.gate);
      await denied;
      await settle();
      expect(runtime.gate.closes, 1);
      expect(closed, isFalse);
      runtime.gate.closing!.complete();
      await closing;
      expect(lease.closes, 0);
    },
  );

  test('late failed identity proof permanently retires every owner', () async {
    final runtime = Runtime(), lease = Lease();
    final authority = prepare(runtime, lease);
    await authority.initialize();
    final a = await authority.bindOwner(Object()),
        b = await authority.bindOwner(Object());
    final pause = runtime.paused = Completer<void>();
    await expectLater(
      authority.validateOwner(a, deadline: const Duration(milliseconds: 10)),
      failure('TIMEOUT'),
    );
    expect(b.isRevoked, isFalse);
    expect(authority.pendingProofs, 1);
    pause.completeError(StateError('UNAUTHORIZED'));
    await settle();
    expect(authority.pendingProofs, 0);
    expect(authority.isStopping, isTrue);
    expect(b.isRevoked, isTrue);
    expect(runtime.gate.isClosed, isTrue);
    expect(() => authority.publicationGate, failure('SERVICE_UNAVAILABLE'));
    runtime.paused =
        null; // Restoring the provider cannot revive the generation.
    await expectLater(
      authority.validateOwner(b),
      failure('SERVICE_UNAVAILABLE'),
    );
    expect(() => authority.initialize(), failure('SERVICE_UNAVAILABLE'));
    expect(() => authority.bindOwner(Object()), failure('SERVICE_UNAVAILABLE'));
    await authority.close();
    expect(lease.closes, 0);
  });

  test('changed owner/lease and provider-private failures fail closed without echo', () async {
    final wrongLease = Lease()..ownerIdentity = 'foreign';
    expect(() => prepare(Runtime(), wrongLease), failure('UNAUTHORIZED'));
    final runtime = Runtime(), lease = Lease();
    final authority = prepare(runtime, lease);
    await authority.initialize();
    final cap = await authority.bindOwner(Object());
    runtime.proofError = StateError('private-provider-value');
    await expectLater(
      authority.validateOwner(cap),
      failure('SERVICE_UNAVAILABLE'),
    );
    expect(cap.isRevoked, isTrue);
    await authority.close();
    expect(lease.closes, 0);
  });
}
