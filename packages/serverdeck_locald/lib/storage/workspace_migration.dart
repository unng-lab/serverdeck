import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../bootstrap/native_runtime.dart';
import 'automation_records.dart';
import 'foundation_snapshot.dart';
import 'key_custody.dart';
import 'migration_journal.dart';
import 'migration_probe.dart';
import 'native_close.dart';
import 'native_schema.dart';
import 'records.dart';
import 'workspace.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');

/// Explicit startup component, not yet called by the schema1 product bootstrap.
/// The same-build1.1 activation gate and operational schema2 store are separate
/// prerequisites. Success here permits subsequent normal full store validation;
/// it does not mean service readiness or grant/mutation admission.
abstract final class WorkspaceMigration {
  static bool _reserved = false;
  static bool get hasOpenReservation => _reserved;

  /// The caller owns and retains the workspace lease. If native close cannot be
  /// confirmed, the reservation remains held and the process must retain its
  /// lease until exit. No active database is ever opened through Isar here.
  static Future<void> run({
    required String localAppData,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
  }) async {
    if (Workspace.hasOpenReservation || Isar.getInstance('workspace') != null)
      _blocked();
    _reserved = true;
    final operation = _Migration(localAppData, lease, custody);
    try {
      operation.owner();
      await initializeNativeRuntime(appRoot);
      await operation.run();
    } catch (error) {
      if (error is StateError &&
          (error.message == 'INCOMPATIBLE' ||
              error.message == 'PREREQUISITE_UNAVAILABLE'))
        rethrow;
      _blocked();
    } finally {
      operation.key?.close();
      if (operation.nativeClosed) _reserved = false;
    }
  }
}

final class _Migration {
  _Migration(this.root, this.lease, this.custody)
    : parent = p.join(root, 'ServerDeckNext', 'v1', 'workspaces');
  final String root, parent;
  final MutexLease lease;
  final KeyCustody custody;
  String get sid => custody.ownerSid;
  String get active => p.join(parent, 'default');
  String get stage => p.join(parent, 'default.upgrading-1-2');
  String activeFile(String name) => p.join(active, name);
  String stageFile(String name) => p.join(stage, name);
  static const names = {
    'migration.json',
    'migration.json.new',
    'workspace.isar',
    'workspace.isar-lck',
    'original.isar',
    'manifest2.json',
  };
  ReceiptKeyMaterial? key;
  bool nativeClosed = true;

  void owner() {
    if (!lease.isHeld || sid != currentUserSid()) _blocked();
  }

  void protected(String path, FileSystemEntityType expected) {
    owner();
    requireSafePath(root, path);
    if (FileSystemEntity.typeSync(path, followLinks: false) != expected)
      _blocked();
    requireOwnerOnlyFileAcl(path, sid);
  }

  Future<Uint8List> bytes(String path, int maximum) async {
    owner();
    return Uint8List.fromList(
      await readProtectedFile(root, path, sid, maxBytes: maximum),
    );
  }

  String digest(List<int> value) => const DartSha256()
      .hashSync(value)
      .bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  Future<String> fileDigest(
    String path, [
    int maximum = 64 * 1024 * 1024,
  ]) async => digest(await bytes(path, maximum));

  Future<void> reserve([int mib = 16]) async {
    owner();
    final required = mib << 20;
    await requireProtectedDiskSpace(
      root,
      parent,
      sid,
      minimumBytes: migrationProbesEnabled
          ? MigrationProbe.minimumFreeBytes(required)
          : required,
    );
  }

  Set<String> inventory() {
    protected(stage, FileSystemEntityType.directory);
    final result = <String>{};
    for (final entry in Directory(stage).listSync(followLinks: false)) {
      final name = p.basename(entry.path);
      if (!names.contains(name) || !result.add(name)) _blocked();
      protected(stageFile(name), FileSystemEntityType.file);
    }
    return result;
  }

  Future<MigrationJournal> journal(String name) async =>
      MigrationJournal.fromJson(
        StrictCodec().decode(
          await bytes(stageFile(name), 4096),
          maxBytes: 4096,
        ),
      );

  void residueMatches(MigrationJournal current, MigrationJournal residue) {
    final left = current.toJson(), right = residue.toJson();
    for (final field in [
      'migrationId',
      'workspaceId',
      'receiptKeyId',
      'ownerSid',
      'sourceDbDigest',
      'sourceManifestDigest',
      'sourceKeyWrapperDigest',
    ]) {
      if (left[field] != right[field]) _blocked();
    }
    if (current.phase == MigrationPhase.prepared &&
        residue.phase == MigrationPhase.prepared &&
        (current.targetDbDigest != residue.targetDbDigest ||
            current.targetManifestDigest != residue.targetManifestDigest ||
            current.sourceRowsDigest != residue.sourceRowsDigest))
      _blocked();
  }

  Future<void> writeJournal(
    MigrationJournal value, {
    required bool replace,
  }) async {
    await reserve();
    final name = replace ? 'migration.json.new' : 'migration.json';
    await writeNewProtectedFile(
      root,
      stageFile(name),
      sid,
      StrictCodec().canonical(value.toJson()),
    );
    if (replace) {
      owner();
      await promoteProtectedPath(
        root,
        stageFile(name),
        stageFile('migration.json'),
        sid,
        replace: true,
      );
    }
    if (digest(
          StrictCodec().canonical((await journal('migration.json')).toJson()),
        ) !=
        digest(StrictCodec().canonical(value.toJson())))
      _blocked();
  }

  void remove(String name) {
    if (!names.contains(name)) _blocked();
    final path = stageFile(name);
    protected(path, FileSystemEntityType.file);
    File(path).deleteSync();
  }

  Future<T> database<T>(int schema, Future<T> Function(Isar) action) async {
    owner();
    protected(stage, FileSystemEntityType.directory);
    protected(stageFile('workspace.isar'), FileSystemEntityType.file);
    protected(stageFile('workspace.isar-lck'), FileSystemEntityType.file);
    if (!nativeClosed || Isar.getInstance('workspace') != null) _blocked();
    Isar? opened;
    // An exceptional open can occur after native allocation. A visible native
    // instance must be closed too; otherwise reservation/lease stay held.
    nativeClosed = false;
    try {
      opened = await Isar.open(
        schema == 1 ? workspaceSchemas : automationWorkspaceSchemas,
        directory: stage,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      owner();
      return await action(opened);
    } finally {
      final instance = opened ?? Isar.getInstance('workspace');
      if (instance != null)
        nativeClosed = await confirmNativeClose(
          migrationProbesEnabled
              ? () => MigrationProbe.closeNative(instance.close)
              : instance.close,
        );
      // A thrown native open without an instance cannot prove native cleanup.
      if (!nativeClosed) _blocked();
    }
  }

  Future<void> probe(MigrationBoundary boundary) async {
    if (migrationProbesEnabled) await MigrationProbe.reached(boundary);
    owner();
  }

  Future<void> verifyBindings(
    MigrationJournal value, {
    required bool target,
  }) async {
    if (await fileDigest(activeFile('workspace.isar')) !=
            (target ? value.targetDbDigest : value.sourceDbDigest) ||
        await fileDigest(activeFile('receipt-key.dpapi'), 16384) !=
            value.sourceKeyWrapperDigest)
      _blocked();
    final manifestHash = await fileDigest(
      activeFile('workspace.manifest.json'),
      4096,
    );
    if (target) {
      if (manifestHash != value.sourceManifestDigest &&
          manifestHash != value.targetManifestDigest)
        _blocked();
    } else if (manifestHash != value.sourceManifestDigest) {
      _blocked();
    }
  }

  Future<void> run() async {
    // Check every product-owned ancestor before any private reads or writes.
    // Do not repair a foreign/permissive ancestor during migration recovery.
    protected(p.join(root, 'ServerDeckNext'), FileSystemEntityType.directory);
    protected(
      p.join(root, 'ServerDeckNext', 'v1'),
      FileSystemEntityType.directory,
    );
    protected(parent, FileSystemEntityType.directory);
    protected(active, FileSystemEntityType.directory);
    protected(activeFile('workspace.isar-lck'), FileSystemEntityType.file);
    final manifestBytes = await bytes(
      activeFile('workspace.manifest.json'),
      4096,
    );
    final manifest = MigrationManifest.fromJson(
      StrictCodec().decode(manifestBytes, maxBytes: 4096),
    );
    if (manifest.ownerSid != sid) _blocked();
    final wrapper = await bytes(activeFile('receipt-key.dpapi'), 16384);
    key = await custody.openReceiptKey(
      wrapper,
      manifest.workspaceId,
      manifest.receiptKeyId,
    );
    final snapshot = await bytes(activeFile('workspace.isar'), 64 << 20);
    final schema = inspectNativeWorkspaceSchema(snapshot);
    final dbHash = digest(snapshot),
        manifestHash = digest(manifestBytes),
        keyHash = digest(wrapper);
    requireSafePath(root, stage);
    final stageType = FileSystemEntity.typeSync(stage, followLinks: false);
    Set<String> files = {};
    if (stageType != FileSystemEntityType.notFound) files = inventory();
    MigrationJournal? current;
    if (files.contains('migration.json')) {
      current = await journal('migration.json');
      if (files.contains('migration.json.new'))
        residueMatches(current, await journal('migration.json.new'));
    } else if (files.isNotEmpty) {
      _blocked();
    }
    final action = assessMigration(
      dbSchema: schema,
      manifest: manifest,
      stage: current != null
          ? StagePresence.journal
          : stageType == FileSystemEntityType.notFound
          ? StagePresence.absent
          : StagePresence.empty,
      journal: current,
      dbDigest: dbHash,
      manifestDigest: manifestHash,
      keyWrapperDigest: keyHash,
      backupDigest: files.contains('original.isar')
          ? await fileDigest(stageFile('original.isar'))
          : null,
    );
    await probe(MigrationBoundary.sourceValidated);
    if (action == MigrationAction.normalOpen) {
      // Normal schema2 validation belongs to the operational store, not the
      // migration-only empty-automation compatibility loader.
      if (stageType != FileSystemEntityType.notFound) {
        if (inventory().isNotEmpty) _blocked();
        Directory(stage).deleteSync();
      }
      return;
    }
    if (action == MigrationAction.prepare ||
        action == MigrationAction.rebuildStage) {
      await reserve(144);
      if (stageType == FileSystemEntityType.notFound)
        createProtectedDirectory(root, stage, sid);
      for (final name in inventory().where((name) => name != 'migration.json'))
        remove(name);
      current = MigrationJournal.fromJson({
        'format': 1,
        'fromSchema': 1,
        'toSchema': 2,
        'migrationId': current?.migrationId ?? _uuid(),
        'workspaceId': manifest.workspaceId,
        'receiptKeyId': manifest.receiptKeyId,
        'ownerSid': sid,
        'sourceDbDigest': dbHash,
        'sourceManifestDigest': manifestHash,
        'sourceKeyWrapperDigest': keyHash,
        'phase': 'preparing',
      });
      await writeJournal(current, replace: files.contains('migration.json'));
      await probe(MigrationBoundary.journalFlushed);
      await reserve();
      await copyProtectedFile(
        root,
        activeFile('workspace.isar'),
        stageFile('original.isar'),
        sid,
      );
      if (await fileDigest(stageFile('original.isar')) !=
          current.sourceDbDigest)
        _blocked();
      await probe(MigrationBoundary.backupCopied);
      await reserve();
      await copyProtectedFile(
        root,
        activeFile('workspace.isar'),
        stageFile('workspace.isar'),
        sid,
      );
      if (await fileDigest(stageFile('workspace.isar')) !=
          current.sourceDbDigest)
        _blocked();
      await createProtectedEmptyFile(
        root,
        stageFile('workspace.isar-lck'),
        sid,
      );
      final sourceRows = await database(
        1,
        (isar) async =>
            (await readFoundationSnapshot(isar, key!, custody)).rows.digest(),
      );
      await probe(MigrationBoundary.sourceRowsValidated);
      await reserve();
      await database(2, (isar) async {
        await probe(MigrationBoundary.nativeSchemaOpened);
        await isar.writeTxn(() async {
          owner();
          final row = await isar.storedWorkspaces.get(1);
          if (row == null) _blocked();
          final metadata = StrictCodec().decode(
            utf8.encode(row.payload),
            maxBytes: 4096,
          );
          if (metadata['schemaVersion'] != 1) _blocked();
          metadata['schemaVersion'] = 2;
          row.payload = utf8.decode(StrictCodec().canonical(metadata));
          await isar.storedWorkspaces.put(row);
          await probe(MigrationBoundary.uncommittedMarker);
        });
        await probe(MigrationBoundary.markerCommitted);
        if ((await readFoundationSnapshot(
              isar,
              key!,
              custody,
              expectedSchema: 2,
            )).rows.digest() !=
            sourceRows)
          _blocked();
      });
      if (inspectNativeWorkspaceSchema(
            await bytes(stageFile('workspace.isar'), 64 << 20),
          ) !=
          2)
        _blocked();
      await probe(MigrationBoundary.candidateClosed);
      final targetManifest = _manifest2(manifest);
      await reserve();
      await writeNewProtectedFile(
        root,
        stageFile('manifest2.json'),
        sid,
        targetManifest,
      );
      current = current.prepare(
        targetDbDigest: await fileDigest(stageFile('workspace.isar')),
        targetManifestDigest: digest(targetManifest),
        sourceRowsDigest: sourceRows,
      );
      await writeJournal(current, replace: true);
      await probe(MigrationBoundary.preparedJournal);
      await verifyBindings(current, target: false);
      if (await fileDigest(stageFile('original.isar')) !=
          current.sourceDbDigest)
        _blocked();
      await reserve();
      owner();
      await promoteProtectedPath(
        root,
        stageFile('workspace.isar'),
        activeFile('workspace.isar'),
        sid,
        replace: true,
      );
      await probe(MigrationBoundary.databasePublished);
    }
    final prepared = current!;
    await verifyBindings(prepared, target: true);
    // Any previous verification copy is expendable; only the frozen active DB
    // and original source backup are bound to physical hashes.
    files = inventory();
    for (final name in ['workspace.isar', 'workspace.isar-lck']) {
      if (files.contains(name)) remove(name);
    }
    await reserve();
    await copyProtectedFile(
      root,
      activeFile('workspace.isar'),
      stageFile('workspace.isar'),
      sid,
    );
    if (await fileDigest(stageFile('workspace.isar')) !=
        prepared.targetDbDigest)
      _blocked();
    await createProtectedEmptyFile(root, stageFile('workspace.isar-lck'), sid);
    if (inspectNativeWorkspaceSchema(
          await bytes(stageFile('workspace.isar'), 64 << 20),
        ) !=
        2)
      _blocked();
    final targetRows = await database(
      2,
      (isar) async => (await readFoundationSnapshot(
        isar,
        key!,
        custody,
        expectedSchema: 2,
      )).rows.digest(),
    );
    if (targetRows != prepared.sourceRowsDigest) _blocked();
    await verifyBindings(prepared, target: true);
    await probe(MigrationBoundary.targetVerified);
    final expectedManifest = _manifest2(manifest);
    if (digest(expectedManifest) != prepared.targetManifestDigest) _blocked();
    final manifestPath = stageFile('manifest2.json');
    if (!inventory().contains('manifest2.json')) {
      await reserve();
      await writeNewProtectedFile(root, manifestPath, sid, expectedManifest);
    }
    if (await fileDigest(manifestPath, 4096) != prepared.targetManifestDigest)
      _blocked();
    await reserve();
    owner();
    await promoteProtectedPath(
      root,
      manifestPath,
      activeFile('workspace.manifest.json'),
      sid,
      replace: true,
    );
    await probe(MigrationBoundary.manifestPublished);
    await verifyBindings(prepared, target: true);
    if (await fileDigest(activeFile('workspace.manifest.json'), 4096) !=
            prepared.targetManifestDigest ||
        inspectNativeWorkspaceSchema(
              await bytes(activeFile('workspace.isar'), 64 << 20),
            ) !=
            2)
      _blocked();
    for (final name in inventory().where((name) => name != 'migration.json')) {
      remove(name);
      await probe(MigrationBoundary.cleanupFile);
    }
    if (inventory().length != 1) _blocked();
    remove('migration.json');
    await probe(MigrationBoundary.journalRemoved);
    if (inventory().isNotEmpty) _blocked();
    Directory(stage).deleteSync();
    await probe(MigrationBoundary.stageRemoved);
  }

  List<int> _manifest2(MigrationManifest source) =>
      StrictCodec().canonical({...source.toJson(), 'format': 2, 'schema': 2});

  String _uuid() {
    final random = Random.secure();
    final value = List.generate(16, (_) => random.nextInt(256));
    value[6] = (value[6] & 15) | 0x40;
    value[8] = (value[8] & 63) | 0x80;
    final hex = value
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
