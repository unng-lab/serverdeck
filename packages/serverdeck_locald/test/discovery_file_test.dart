import 'dart:io';
import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/discovery.dart';
import 'package:serverdeck_locald/bootstrap/discovery_file.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

void main() {
  test('owned discovery publishes atomically, rejects contender, and removes only its generation', () async {
    final parent = Directory.systemTemp.createTempSync(
      'serverdeck-discovery-fixture-',
    );
    final root = p.normalize(p.absolute(parent.path));
    final sid = currentUserSid();
    final runtime = p.join(root, 'runtime');
    createProtectedDirectory(root, runtime, sid);
    final namespace = await DiscoveryNamespace.forOwner(sid);
    final lease = await MutexLease.acquire(namespace.mutexName, sid);
    final build = '${'a' * 40}+Debug+${'b' * 64}';
    final descriptor = await DiscoveryDescriptor.create(
      ownerSid: sid,
      buildId: build,
      serverPid: pid,
    );
    final file = DiscoveryFile(
      localAppData: root,
      runtimeDirectory: runtime,
      ownerSid: sid,
      custody: DiscoveryCustody(DpapiProtection(), sid),
    );
    try {
      expect(lease.isHeld, true);
      await file.publish(descriptor, lease);
      final starting = await file.read(build);
      try {
        expect(starting.workspaceId, isNull);
        expect(starting.bootstrapToken, descriptor.bootstrapToken);
      } finally {
        starting.close();
      }
      final before = File(file.path).readAsBytesSync();
      final loser = await MutexLease.acquire(namespace.mutexName, sid);
      try {
        expect(loser.isHeld, false);
        await expectLater(file.publish(descriptor, loser), throwsStateError);
        expect(File(file.path).readAsBytesSync(), before);
      } finally {
        await loser.close();
      }
      final ready = descriptor.withWorkspace(
        '12345678-1234-4234-9234-123456789abc',
      );
      final gatedProtection = OverlappingProtection();
      final gatedCustody = DiscoveryCustody(gatedProtection, sid);
      final firstPublisher = DiscoveryFile(
        localAppData: root,
        runtimeDirectory: runtime,
        ownerSid: sid,
        custody: gatedCustody,
      );
      final secondPublisher = DiscoveryFile(
        localAppData: root,
        runtimeDirectory: runtime,
        ownerSid: sid,
        custody: gatedCustody,
      );
      final retainedStarting = ProtectedSnapshotReader.open(
        root,
        file.path,
        sid,
        maxBytes: 16384,
      );
      final firstPublication = firstPublisher
          .publish(ready, lease)
          .then((_) => true, onError: (Object _, StackTrace __) => false);
      final other = descriptor.withWorkspace(
        '12345678-1234-4234-9234-123456789abd',
      );
      try {
        await gatedProtection.firstEntered.future.timeout(
          const Duration(seconds: 5),
        );
        final secondPublication = secondPublisher
            .publish(other, lease)
            .then<Object>(
              (_) => 'unexpected success',
              onError: (Object error, StackTrace __) =>
                  error is StateError ? error.message : 'UNSAFE_ERROR_TYPE',
            );
        var drained = false;
        final sharedDrain = file.drained.then((_) {
          drained = true;
        });
        // Keep the first native write held while the other publisher is active.
        // A shared queue prevents its protection callback from entering.
        await Future.any([
          gatedProtection.secondEntered.future,
          Future<void>.delayed(const Duration(milliseconds: 500)),
        ]);
        expect(drained, false);
        gatedProtection.release.complete();
        expect(await firstPublication, true);
        expect(await secondPublication, 'STORAGE_BLOCKED');
        await sharedDrain;
        expect(gatedProtection.protectCalls, 1);
        await secondPublisher.drained;
        final previous = await DiscoveryCustody(
          DpapiProtection(),
          sid,
        ).unprotect(retainedStarting.read(), build);
        try {
          expect(previous.workspaceId, isNull);
          expect(previous.generation, descriptor.generation);
        } finally {
          previous.close();
        }
      } finally {
        retainedStarting.close();
        if (!gatedProtection.release.isCompleted)
          gatedProtection.release.complete();
        await firstPublication;
        ready.close();
        other.close();
      }
      final opened = await file.read(build);
      try {
        expect(opened.workspaceId, '12345678-1234-4234-9234-123456789abc');
        expect(opened.generation, descriptor.generation);
      } finally {
        opened.close();
      }
      final boundBytes = File(file.path).readAsBytesSync();
      await expectLater(file.publish(descriptor, lease), throwsStateError);
      expect(File(file.path).readAsBytesSync(), boundBytes);
      final reopenedPublisher = DiscoveryFile(
        localAppData: root,
        runtimeDirectory: runtime,
        ownerSid: sid,
        custody: DiscoveryCustody(DpapiProtection(), sid),
      );
      await expectLater(
        reopenedPublisher.publish(descriptor, lease),
        throwsStateError,
      );
      expect(File(file.path).readAsBytesSync(), boundBytes);
      final foreignWorkspace = descriptor.withWorkspace(
        '12345678-1234-4234-9234-123456789abd',
      );
      try {
        await expectLater(
          file.publish(foreignWorkspace, lease),
          throwsStateError,
        );
        expect(File(file.path).readAsBytesSync(), boundBytes);
      } finally {
        foreignWorkspace.close();
      }
      await expectLater(
        file.remove('12345678-1234-4234-9234-123456789abd', build, lease),
        throwsStateError,
      );
      expect(File(file.path).existsSync(), true);
      final unsafe = DiscoveryFile(
        localAppData: root,
        runtimeDirectory: p.join(root, 'missing-runtime'),
        ownerSid: sid,
        custody: DiscoveryCustody(DpapiProtection(), sid),
      );
      await expectLater(
        unsafe.remove(descriptor.generation, build, lease),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'safe code',
            'STORAGE_BLOCKED',
          ),
        ),
      );
      expect(File(file.path).existsSync(), true);
      final newerBuild = '${'c' * 40}+Debug+${'b' * 64}';
      final replacement = await DiscoveryDescriptor.create(
        ownerSid: sid,
        buildId: newerBuild,
        serverPid: pid,
      );
      try {
        await file.publish(replacement, lease);
        final rotated = await file.read(newerBuild);
        try {
          expect(rotated.generation, replacement.generation);
          expect(rotated.workspaceId, isNull);
        } finally {
          rotated.close();
        }
        await file.remove(replacement.generation, newerBuild, lease);
        expect(File(file.path).existsSync(), false);
      } finally {
        replacement.close();
      }
      await file.drained;
      await lease.close();
      await expectLater(file.publish(descriptor, lease), throwsStateError);
      expect(File(file.path).existsSync(), false);
      stdout.writeln('NATIVE_DISCOVERY_PUBLICATION_PROVED');
    } finally {
      descriptor.close();
      await file.drained;
      await lease.close();
      if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root))
        throw StateError('UNSAFE_TEST_DIRECTORY');
      parent.deleteSync(recursive: true);
    }
  });
}

class OverlappingProtection implements UserProtection {
  final actual = DpapiProtection();
  final firstEntered = Completer<void>(),
      secondEntered = Completer<void>(),
      release = Completer<void>();
  int protectCalls = 0;
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) async {
    protectCalls++;
    if (protectCalls == 1) firstEntered.complete();
    if (protectCalls == 2) secondEntered.complete();
    await release.future;
    return actual.protect(cleartext, entropy);
  }

  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) =>
      actual.unprotect(ciphertext, entropy);
}
