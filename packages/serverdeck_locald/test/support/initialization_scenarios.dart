import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/initialization_probe.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/workspace.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import 'state_store_child.dart' show check;
import 'private_marker_scan.dart';

class _InitializationProtection implements UserProtection {
  final delegate = DpapiProtection();
  final scan = PrivateMarkerScan();
  bool observed = false;
  void observe(List<int> clear) {
    final value = StrictCodec().decode(clear, maxBytes: 8192);
    if (value['receiptKey'] case final String encoded when !observed) {
      final bytes = base64.decode(encoded);
      try {
        check(bytes.length == 32);
        scan.addSecretBytes(bytes);
        observed = true;
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  @override
  Future<List<int>> protect(List<int> clear, List<int> entropy) async {
    observe(clear);
    return delegate.protect(clear, entropy);
  }

  @override
  Future<List<int>> unprotect(List<int> value, List<int> entropy) async {
    final clear = await delegate.unprotect(value, entropy);
    try {
      observe(clear);
      return clear;
    } catch (_) {
      clear.fillRange(0, clear.length, 0);
      rethrow;
    }
  }
}

const initializationCases =
    <
      String,
      ({InitializationBoundary point, bool ready, int files, bool active})
    >{
      'init-staging-created': (
        point: InitializationBoundary.stagingCreated,
        ready: false,
        files: 0,
        active: false,
      ),
      'init-key-flushed': (
        point: InitializationBoundary.keyFlushed,
        ready: false,
        files: 1,
        active: false,
      ),
      'init-manifest-flushed': (
        point: InitializationBoundary.manifestFlushed,
        ready: false,
        files: 2,
        active: false,
      ),
      'init-native-files-created': (
        point: InitializationBoundary.nativeFilesCreated,
        ready: false,
        files: 4,
        active: false,
      ),
      'init-uncommitted-initial-rows': (
        point: InitializationBoundary.uncommittedInitialRows,
        ready: false,
        files: 4,
        active: false,
      ),
      'init-initial-transaction-durable': (
        point: InitializationBoundary.initialTransactionDurable,
        ready: true,
        files: 4,
        active: false,
      ),
      'init-before-promotion': (
        point: InitializationBoundary.beforePromotion,
        ready: true,
        files: 4,
        active: false,
      ),
      'init-after-promotion': (
        point: InitializationBoundary.afterPromotion,
        ready: true,
        files: 4,
        active: true,
      ),
      'init-active-opened': (
        point: InitializationBoundary.activeOpened,
        ready: true,
        files: 4,
        active: true,
      ),
      // Separate single-use case for a deliberate inventory replacement.
      'init-native-files-inventory-replaced': (
        point: InitializationBoundary.nativeFilesCreated,
        ready: false,
        files: 4,
        active: false,
      ),
    };

Future<void> run(
  String root,
  String bundle,
  String name, {
  required bool verify,
}) async {
  final scenario = initializationCases[name]!;
  check(initializationProbesEnabled);
  final sid = currentUserSid();
  final digest = await Sha256().hash(utf8.encode('compiled-init-crash-$root'));
  final mutex =
      'Global\\ServerDeckNext.v1.${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  final lease = await MutexLease.acquire(mutex, sid);
  check(lease.isHeld);
  final active = p.join(root, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  final staging = '$active.creating';
  final snapshotPath = p.join(root, 'initialization-boundary.json');
  final protection = _InitializationProtection();
  String? scanFailure;
  final noKey = scenario.files == 0;
  final deferredLiveScan =
      !verify &&
      scenario.point == InitializationBoundary.uncommittedInitialRows;
  String getMarker() => noKey
      ? 'INIT_NO_SECRET_CREATED_PROVED'
      : deferredLiveScan
      ? 'INIT_RECEIPT_KEY_LIVE_SCAN_DEFERRED_PROVED'
      : 'INIT_RECEIPT_KEY_MARKERS_CLEAN_PROVED';
  Future<void> scanTree() async {
    check(protection.observed == !noKey);
    requireSafePath(root, root);
    requireOwnerOnlyFileAcl(root, sid);
    var files = 0;
    var deferredFiles = 0;
    for (final entry in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      requireSafePath(root, entry.path);
      requireOwnerOnlyFileAcl(entry.path, sid);
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      check(
        type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory,
      );
      if (type == FileSystemEntityType.file) {
        if (noKey) {
          check(entry.path == snapshotPath);
        } else if (deferredLiveScan &&
            (entry.path == p.join(staging, 'workspace.isar') ||
                entry.path == p.join(staging, 'workspace.isar-lck'))) {
          // Windows rejected a live transaction file read with error33.
          // Do not retry it or substitute another reader. Both native files
          // remain outside this live file scan; the fresh verifier scans them
          // only after the owned crashed process has actually terminated.
          deferredFiles++;
        } else {
          try {
            await protection.scan.assertCleanFile(File(entry.path));
          } on FileSystemException catch (error) {
            throw StateError(
              'INIT_SCAN_READ_IO_${error.osError?.errorCode ?? 0}',
            );
          }
        }
        files++;
      }
    }
    check(noKey ? files == 1 : files >= scenario.files + 1);
    check(deferredFiles == (deferredLiveScan ? 2 : 0));
  }

  Future<void> checkedScan() => scanTree().catchError((Object error) {
    scanFailure =
        error is StateError &&
            (error.message == 'PRIVATE_MARKER_FOUND' ||
                RegExp(r'^INIT_SCAN_READ_IO_-?\d+$')
                    .hasMatch('${error.message}'))
        ? error.message == 'PRIVATE_MARKER_FOUND'
              ? 'INIT_SCAN_PRIVATE_MARKER_FOUND'
              : error.message
        : 'INIT_SCAN_READ_OTHER';
    throw error;
  });

  void inspect(String directory, {required bool isActive, required int files}) {
    check(Directory(active).existsSync() == isActive);
    check(Directory(staging).existsSync() == !isActive);
    requireSafePath(root, directory);
    requireOwnerOnlyFileAcl(directory, sid);
    final entries = Directory(directory).listSync(followLinks: false);
    check(entries.length == files);
    final expected = switch (files) {
      0 => <String>{},
      1 => {'receipt-key.dpapi'},
      2 => {'receipt-key.dpapi', 'workspace.manifest.json'},
      4 => {
        'receipt-key.dpapi',
        'workspace.manifest.json',
        'workspace.isar',
        'workspace.isar-lck',
      },
      _ => throw StateError('UNEXPECTED_INITIALIZATION_INVENTORY'),
    };
    check(
      entries
          .map((entry) => p.basename(entry.path))
          .toSet()
          .containsAll(expected),
    );
    for (final entry in entries) {
      check(
        FileSystemEntity.typeSync(entry.path, followLinks: false) ==
            FileSystemEntityType.file,
      );
      requireSafePath(root, entry.path);
      requireOwnerOnlyFileAcl(entry.path, sid);
    }
  }

  Map<String, String> identities(String directory) => {
    for (final file in ['receipt-key.dpapi', 'workspace.manifest.json'])
      if (File(p.join(directory, file)).existsSync())
        file: fileSha256(p.join(directory, file)),
  };

  Workspace? workspace;
  try {
    Map<String, Object?>? snapshot;
    if (verify) {
      snapshot = (jsonDecode(
        utf8.decode(
          await readProtectedFile(root, snapshotPath, sid, maxBytes: 4096),
        ),
      ) as Map).cast<String, Object?>();
      check(
        snapshot.length == 3 &&
            snapshot['format'] == 1 &&
            snapshot['case'] == name,
      );
      final recorded = (snapshot['identities'] as Map).cast<String, String>();
      final inspected = scenario.active ? active : staging;
      inspect(inspected, isActive: scenario.active, files: scenario.files);
      check(jsonEncode(identities(inspected)) == jsonEncode(recorded));
      if (!noKey) {
        // A partial stage may be rejected before production unwrap. Bind the
        // oracle by reading its original protected wrapper without changing it.
        final clear = await protection.unprotect(
          await readProtectedFile(
            root,
            p.join(inspected, 'receipt-key.dpapi'),
            sid,
            maxBytes: 16384,
          ),
          utf8.encode('ServerDeckNext\nv1\ndefault\n$sid\nreceipt'),
        );
        clear.fillRange(0, clear.length, 0);
      }
      await checkedScan();
    } else {
      InitializationProbe.install((point) async {
        if (point != scenario.point) return;
        final inspected = scenario.active ? active : staging;
        inspect(inspected, isActive: scenario.active, files: scenario.files);
        await writeNewProtectedFile(
          root,
          snapshotPath,
          sid,
          utf8.encode(
            jsonEncode({
              'format': 1,
              'case': name,
              'identities': identities(inspected),
            }),
          ),
        );
        await checkedScan();
        stdout.writeln(getMarker());
        stdout.writeln('CRASH_BOUNDARY');
        await stdout.flush();
        await Completer<void>().future;
      });
    }
    try {
      workspace = await Workspace.open(
        localAppData: root,
        appRoot: bundle,
        lease: lease,
        custody: KeyCustody(protection, sid),
      );
    } on StateError catch (error) {
      if (!verify && scanFailure != null) throw StateError(scanFailure!);
      check(verify && !scenario.ready && error.message == 'STORAGE_BLOCKED');
      inspect(staging, isActive: false, files: scenario.files);
      check(
        jsonEncode(identities(staging)) == jsonEncode(snapshot!['identities']),
      );
      await checkedScan();
      stdout.writeln(getMarker());
      stdout.writeln('INIT_PARTIAL_PRESERVED_PROVED');
      return;
    }
    check(verify && scenario.ready && workspace.store.state.isInitialEmpty);
    inspect(active, isActive: true, files: 4);
    check(
      jsonEncode(identities(active)) == jsonEncode(snapshot!['identities']),
    );
    await checkedScan();
    stdout.writeln(getMarker());
    stdout.writeln('INIT_READY_PROVED');
  } finally {
    await workspace?.close();
    protection.scan.close();
    await lease.close();
  }
}
