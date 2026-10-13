import 'dart:convert';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/lifecycle.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../auth_test.dart' show generation;
import 'state_store_child.dart' show check, rejects;

/// Test-only validation fault: native instance is closed before custody fails,
/// so StateStore's own cleanup returns false. This models an unconfirmed close
/// result, not a claim that the already closed fixture leaks a native handle.
class ClosedCredentialFailure implements UserProtection {
  final actual = DpapiProtection();
  bool triggered = false;
  @override
  Future<List<int>> protect(List<int> bytes, List<int> entropy) =>
      actual.protect(bytes, entropy);
  @override
  Future<List<int>> unprotect(List<int> bytes, List<int> entropy) async {
    if (utf8.decode(entropy).endsWith('\ncredential')) {
      check(await Isar.getInstance('workspace')!.close());
      triggered = true;
      throw StateError('PROTECTION_UNAVAILABLE');
    }
    return actual.unprotect(bytes, entropy);
  }
}

Future<void> verifyOpenCloseFailure(
  String root,
  String bundle,
  String directory,
  MutexLease lease,
  String sid,
) async {
  final product = p.join(root, 'ServerDeckNext'),
      version = p.join(product, 'v1'),
      parent = p.join(version, 'workspaces');
  for (final path in [product, version, parent])
    createProtectedDirectory(root, path, sid);
  final active = p.join(parent, 'default');
  check(p.equals(directory, active));
  final protection = ClosedCredentialFailure();
  await rejects(
    Workspace.open(
      localAppData: root,
      appRoot: bundle,
      lease: lease,
      custody: KeyCustody(protection, sid),
    ),
    'STORAGE_BLOCKED',
  );
  check(protection.triggered && Workspace.hasOpenReservation);
  final calls = <String>[];
  final service = ServiceLifecycle(
    generation: generation,
    resources: ShutdownResources(
      cancelStartup: () async {
        calls.add('startup');
      },
      drainMutations: () async {
        calls.add('mutations');
      },
      closeStorage: () async {
        calls.add('storage');
        Workspace.requireNoOpenReservation();
      },
      closePipes: () async {
        calls.add('pipes');
      },
      removeDiscovery: () async {
        calls.add('discovery');
      },
      clearKeys: () async {
        calls.add('keys');
      },
      releaseMutex: () async {
        calls.add('release');
        await lease.close();
      },
    ),
  );
  await rejects(service.close(), 'STORAGE_BLOCKED');
  check(calls.join(',') == 'startup,mutations,storage' && lease.isHeld);
}
