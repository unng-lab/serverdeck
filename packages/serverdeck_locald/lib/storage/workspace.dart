import 'dart:io';
import 'dart:math';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../bootstrap/native_runtime.dart';
import 'key_custody.dart';
import 'initialization_probe.dart';
import 'models.dart';
import 'records.dart';
import 'state_store.dart';

/// Owns creation/promotion and receipt-key lifetime; the caller owns the lease.
class Workspace {
  Workspace._(this._store, this._receiptKey);
  static bool _reserved = false;

  /// An unsuccessful open can retain this reservation if native close failed.
  /// The resource owner must not release its mutex in that case.
  static bool get hasOpenReservation =>
      _reserved || StateStore.hasOpenReservation;
  static void requireNoOpenReservation() {
    if (hasOpenReservation) throw StateError('STORAGE_BLOCKED');
  }

  final StateStore _store;
  final ReceiptKeyMaterial _receiptKey;
  Future<void>? _closing;

  static Future<Workspace> open({
    required String localAppData,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    void Function()? checkStartup,
  }) async {
    if (_reserved) throw StateError('STORAGE_BLOCKED');
    _reserved = true;
    ReceiptKeyMaterial? key;
    StateStore? store;
    Isar? initial;
    var transferred = false, safeToRelease = true;
    void owner() {
      checkStartup?.call();
      if (!lease.isHeld || custody.ownerSid != currentUserSid()) {
        throw StateError('STORAGE_BLOCKED');
      }
    }

    Future<StateStore> openStore(String directory) => StateStore.open(
      localAppData: localAppData,
      directory: directory,
      appRoot: appRoot,
      lease: lease,
      custody: custody,
      receiptKey: key!,
    );
    try {
      owner();
      await initializeNativeRuntime(appRoot);
      if (Isar.getInstance('workspace') != null) {
        throw StateError('STORAGE_BLOCKED');
      }
      final product = p.join(localAppData, 'ServerDeckNext');
      final version = p.join(product, 'v1');
      final parent = p.join(version, 'workspaces');
      for (final directory in [product, version, parent]) {
        owner();
        createProtectedDirectory(localAppData, directory, custody.ownerSid);
      }
      final active = p.join(parent, 'default'), staging = '$active.creating';
      requireSafePath(localAppData, active);
      requireSafePath(localAppData, staging);
      final activeType = FileSystemEntity.typeSync(active, followLinks: false);
      final stagingType = FileSystemEntity.typeSync(
        staging,
        followLinks: false,
      );
      if ((activeType != FileSystemEntityType.notFound &&
              stagingType != FileSystemEntityType.notFound) ||
          (activeType != FileSystemEntityType.notFound &&
              activeType != FileSystemEntityType.directory) ||
          (stagingType != FileSystemEntityType.notFound &&
              stagingType != FileSystemEntityType.directory)) {
        throw StateError('STORAGE_BLOCKED');
      }
      if (activeType == FileSystemEntityType.directory) {
        key = await _readKey(localAppData, active, custody);
        owner();
        store = await openStore(active);
      } else {
        if (stagingType == FileSystemEntityType.notFound) {
          owner();
          createProtectedDirectory(localAppData, staging, custody.ownerSid);
          if (initializationProbesEnabled) {
            await InitializationProbe.reached(
              InitializationBoundary.stagingCreated,
            );
          }
          key = await custody.createReceiptKey(_uuid(), _uuid());
          owner();
          await writeNewProtectedFile(
            localAppData,
            p.join(staging, 'receipt-key.dpapi'),
            custody.ownerSid,
            key.wrapper,
          );
          if (initializationProbesEnabled) {
            await InitializationProbe.reached(
              InitializationBoundary.keyFlushed,
            );
          }
          await writeNewProtectedFile(
            localAppData,
            p.join(staging, 'workspace.manifest.json'),
            custody.ownerSid,
            StrictCodec().encode(
              await custody.createWorkspaceManifest(key),
              maxBytes: 4096,
            ),
          );
          if (initializationProbesEnabled) {
            await InitializationProbe.reached(
              InitializationBoundary.manifestFlushed,
            );
          }
          for (final name in ['workspace.isar', 'workspace.isar-lck']) {
            owner();
            await createProtectedEmptyFile(
              localAppData,
              p.join(staging, name),
              custody.ownerSid,
            );
          }
          owner();
          if (initializationProbesEnabled) {
            await InitializationProbe.reached(
              InitializationBoundary.nativeFilesCreated,
            );
          }
          initial = await Isar.open(
            workspaceSchemas,
            directory: staging,
            name: 'workspace',
            maxSizeMiB: 64,
            relaxedDurability: false,
            inspector: false,
          );
          final rows = WorkspaceRecords.fromState(
            WorkspaceState.empty(
              workspaceId: key.workspaceId,
              receiptKeyId: key.receiptKeyId,
              ownerSid: custody.ownerSid,
            ),
          );
          final database = initial;
          await database.writeTxn(() async {
            owner();
            await database.storedWorkspaces.put(rows.workspace);
            await database.storedSettings.put(rows.settings);
            if (initializationProbesEnabled) {
              await InitializationProbe.reached(
                InitializationBoundary.uncommittedInitialRows,
              );
            }
          });
          if (initializationProbesEnabled) {
            await InitializationProbe.reached(
              InitializationBoundary.initialTransactionDurable,
            );
          }
          if (!await database.close()) throw StateError('STORAGE_BLOCKED');
          initial = null;
        } else {
          key = await _readKey(localAppData, staging, custody);
        }
        owner();
        store = await openStore(staging);
        if (!store.state.isInitialEmpty) throw StateError('STORAGE_BLOCKED');
        await store.close();
        store = null;
        owner();
        if (initializationProbesEnabled) {
          await InitializationProbe.reached(
            InitializationBoundary.beforePromotion,
          );
        }
        await promoteProtectedPath(
          localAppData,
          staging,
          active,
          custody.ownerSid,
        );
        if (initializationProbesEnabled) {
          await InitializationProbe.reached(
            InitializationBoundary.afterPromotion,
          );
        }
        owner();
        store = await openStore(active);
      }
      owner();
      if (initializationProbesEnabled) {
        await InitializationProbe.reached(InitializationBoundary.activeOpened);
      }
      transferred = true;
      return Workspace._(store, key);
    } catch (error) {
      if (store != null) {
        try {
          await store.close();
        } catch (_) {
          safeToRelease = false;
        }
      }
      if (initial != null) {
        try {
          safeToRelease = await initial.close() && safeToRelease;
        } catch (_) {
          safeToRelease = false;
        }
      }
      if (error is StateError &&
          (error.message == 'INCOMPATIBLE' ||
              error.message == 'PREREQUISITE_UNAVAILABLE'))
        rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      if (!transferred) {
        key?.close();
        if (safeToRelease) _reserved = false;
      }
    }
  }

  static Future<ReceiptKeyMaterial> _readKey(
    String localAppData,
    String directory,
    KeyCustody custody,
  ) async {
    requireSafePath(localAppData, directory);
    requireOwnerOnlyFileAcl(directory, custody.ownerSid);
    final manifest = StrictCodec().decode(
      await readProtectedFile(
        localAppData,
        p.join(directory, 'workspace.manifest.json'),
        custody.ownerSid,
        maxBytes: 4096,
      ),
      maxBytes: 4096,
    );
    requireFields(manifest, {
      'product',
      'schema',
      'workspaceId',
      'receiptKeyId',
      'ownerSid',
    });
    if (manifest['schema'] is! int || manifest['schema'] != 1) {
      throw StateError('INCOMPATIBLE');
    }
    if (manifest['product'] != 'serverdeck-next' ||
        manifest['ownerSid'] != custody.ownerSid) {
      throw StateError('STORAGE_BLOCKED');
    }
    requireUuid(manifest['workspaceId']);
    requireUuid(manifest['receiptKeyId']);
    final key = await custody.openReceiptKey(
      await readProtectedFile(
        localAppData,
        p.join(directory, 'receipt-key.dpapi'),
        custody.ownerSid,
        maxBytes: 16384,
      ),
      manifest['workspaceId'] as String,
      manifest['receiptKeyId'] as String,
    );
    try {
      await custody.verifyWorkspaceManifest(manifest, key);
      return key;
    } catch (_) {
      key.close();
      rethrow;
    }
  }

  static String _uuid() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 0x40;
    bytes[8] = (bytes[8] & 63) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  StateStore get store => _store;
  ReceiptKeyMaterial get receiptKey => _receiptKey;
  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      await _store.close();
      _reserved = false;
    } finally {
      _receiptKey.close();
    }
  }
}
