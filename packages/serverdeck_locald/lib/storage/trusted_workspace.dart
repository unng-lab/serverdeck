part of 'workspace.dart';

/// Schema3 creation/migration owner. No server service/SSH is started here.
Future<Workspace> _openTrustedWorkspace({
  required String localAppData,
  required String appRoot,
  required MutexLease lease,
  required KeyCustody custody,
  void Function()? checkStartup,
}) async {
  if (Workspace.hasOpenReservation || Isar.getInstance('workspace') != null)
    throw StateError('STORAGE_BLOCKED');
  Workspace._reserved = true;
  ReceiptKeyMaterial? key;
  StateStore? store;
  Isar? database;
  var transferred = false, closed = true, openingStage = false;
  void owner() {
    checkStartup?.call();
    if (!lease.isHeld || custody.ownerSid != currentUserSid())
      throw StateError('STORAGE_BLOCKED');
  }

  final parent = p.join(localAppData, 'ServerDeckNext', 'v1', 'workspaces');
  final active = p.join(parent, 'default'),
      stage = p.join(parent, 'default.creating');
  try {
    owner();
    await initializeTrustedNativeRuntime(appRoot);
    owner();
    for (final path in [
      p.join(localAppData, 'ServerDeckNext'),
      p.join(localAppData, 'ServerDeckNext', 'v1'),
      parent,
    ]) {
      createProtectedDirectory(localAppData, path, custody.ownerSid);
      owner();
    }
    requireSafePath(localAppData, active);
    requireSafePath(localAppData, stage);
    final activeType = FileSystemEntity.typeSync(active, followLinks: false);
    final stageType = FileSystemEntity.typeSync(stage, followLinks: false);
    if ((activeType != FileSystemEntityType.notFound &&
            activeType != FileSystemEntityType.directory) ||
        (stageType != FileSystemEntityType.notFound &&
            stageType != FileSystemEntityType.directory) ||
        (activeType != FileSystemEntityType.notFound &&
            stageType != FileSystemEntityType.notFound))
      throw StateError('STORAGE_BLOCKED');
    if (activeType == FileSystemEntityType.directory) {
      final manifest = StrictCodec().decode(
        await readProtectedFile(
          localAppData,
          p.join(active, 'workspace.manifest.json'),
          custody.ownerSid,
          maxBytes: 4096,
        ),
        maxBytes: 4096,
      );
      var residue = false;
      for (final suffix in ['.upgrading-1-2', '.upgrading-2-3']) {
        final path = '$active$suffix';
        requireSafePath(localAppData, path);
        residue |=
            FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.notFound;
      }
      // Migration has its own synchronous reservation and retains the same
      // caller-owned writer mutex across both supported upgrade steps.
      if (manifest['format'] != 3 || manifest['schema'] != 3 || residue) {
        Workspace._reserved = false;
        try {
          await WorkspaceMigration.runTrusted(
            localAppData: localAppData,
            appRoot: appRoot,
            lease: lease,
            custody: custody,
          );
        } finally {
          Workspace._reserved = true;
          if (WorkspaceMigration.hasOpenReservation) closed = false;
        }
      }
      owner();
      key = await _trustedWorkspaceKey(localAppData, active, custody);
    } else {
      for (final suffix in ['.upgrading-1-2', '.upgrading-2-3']) {
        final residue = '$active$suffix';
        requireSafePath(localAppData, residue);
        if (FileSystemEntity.typeSync(residue, followLinks: false) !=
            FileSystemEntityType.notFound)
          throw StateError('STORAGE_BLOCKED');
      }
      if (stageType == FileSystemEntityType.notFound) {
        createProtectedDirectory(localAppData, stage, custody.ownerSid);
        key = await custody.createReceiptKey(
          Workspace._uuid(),
          Workspace._uuid(),
        );
        owner();
        await writeNewProtectedFile(
          localAppData,
          p.join(stage, 'receipt-key.dpapi'),
          custody.ownerSid,
          key.wrapper,
        );
        await writeNewProtectedFile(
          localAppData,
          p.join(stage, 'workspace.manifest.json'),
          custody.ownerSid,
          StrictCodec().encode(
            await custody.createTrustedWorkspaceManifest(key),
            maxBytes: 4096,
          ),
        );
        for (final name in ['workspace.isar', 'workspace.isar-lck']) {
          owner();
          await createProtectedEmptyFile(
            localAppData,
            p.join(stage, name),
            custody.ownerSid,
          );
        }
        _trustedCreationInventory(localAppData, stage, custody.ownerSid);
        openingStage = true;
        closed = false;
        database = await Isar.open(
          trustedWorkspaceSchemas,
          directory: stage,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
        final rows = WorkspaceRecords.fromTrustedState(
          WorkspaceState.emptyTrusted(
            workspaceId: key.workspaceId,
            receiptKeyId: key.receiptKeyId,
            ownerSid: custody.ownerSid,
          ),
        );
        final creating = database;
        await creating.writeTxn(() async {
          owner();
          await creating.storedWorkspaces.put(rows.workspace);
          await creating.storedSettings.put(rows.settings);
        });
      } else {
        _trustedCreationInventory(localAppData, stage, custody.ownerSid);
        key = await _trustedWorkspaceKey(localAppData, stage, custody);
        openingStage = true;
        closed = false;
        database = await Isar.open(
          trustedWorkspaceSchemas,
          directory: stage,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
      }
      owner();
      await readTrustedInitialWorkspace(
        database,
        key,
        custody,
        localAppData: localAppData,
        lease: lease,
      );
      owner();
      if (!await database.close()) throw StateError('STORAGE_BLOCKED');
      database = null;
      openingStage = false;
      closed = true;
      _trustedCreationInventory(localAppData, stage, custody.ownerSid);
      owner();
      await promoteProtectedPath(localAppData, stage, active, custody.ownerSid);
    }
    owner();
    Workspace._reserved = false;
    store = await StateStore.openTrustedOperational(
      localAppData: localAppData,
      appRoot: appRoot,
      lease: lease,
      custody: custody,
      receiptKey: key,
    );
    Workspace._reserved = true;
    owner();
    transferred = true;
    return Workspace._(store, key);
  } catch (error) {
    if (store != null) {
      try {
        await store.close();
      } catch (_) {
        closed = false;
      }
    }
    final registered = openingStage ? Isar.getInstance('workspace') : null;
    final candidate =
        database ??
        (registered != null &&
                registered.directory != null &&
                p.equals(p.normalize(p.absolute(registered.directory!)), stage)
            ? registered
            : null);
    if (candidate != null) {
      try {
        closed = await candidate.close();
      } catch (_) {
        closed = false;
      }
    }
    if (StateStore.hasOpenReservation || WorkspaceMigration.hasOpenReservation)
      closed = false;
    if (error is StateError &&
        const {
          'INCOMPATIBLE',
          'PREREQUISITE_UNAVAILABLE',
          'TIMEOUT',
        }.contains(error.message))
      rethrow;
    throw StateError('STORAGE_BLOCKED');
  } finally {
    if (!transferred) {
      key?.close();
      Workspace._reserved = !closed;
    }
  }
}

void _trustedCreationInventory(String root, String stage, String sid) {
  requireSafePath(root, stage);
  requireOwnerOnlyFileAcl(stage, sid);
  final names = <String>{};
  for (final entry in Directory(stage).listSync(followLinks: false)) {
    final name = p.basename(entry.path);
    if (!const {
          'workspace.isar',
          'workspace.isar-lck',
          'receipt-key.dpapi',
          'workspace.manifest.json',
        }.contains(name) ||
        !names.add(name) ||
        FileSystemEntity.typeSync(entry.path, followLinks: false) !=
            FileSystemEntityType.file)
      throw StateError('STORAGE_BLOCKED');
    requireSafePath(root, entry.path);
    requireOwnerOnlyFileAcl(entry.path, sid);
  }
  if (names.length != 4) throw StateError('STORAGE_BLOCKED');
}

Future<ReceiptKeyMaterial> _trustedWorkspaceKey(
  String root,
  String directory,
  KeyCustody custody,
) async {
  requireSafePath(root, directory);
  requireOwnerOnlyFileAcl(directory, custody.ownerSid);
  final manifest = StrictCodec().decode(
    await readProtectedFile(
      root,
      p.join(directory, 'workspace.manifest.json'),
      custody.ownerSid,
      maxBytes: 4096,
    ),
    maxBytes: 4096,
  );
  requireUuid(manifest['workspaceId']);
  requireUuid(manifest['receiptKeyId']);
  final key = await custody.openReceiptKey(
    await readProtectedFile(
      root,
      p.join(directory, 'receipt-key.dpapi'),
      custody.ownerSid,
      maxBytes: 16384,
    ),
    manifest['workspaceId'] as String,
    manifest['receiptKeyId'] as String,
  );
  try {
    await custody.verifyTrustedWorkspaceManifest(manifest, key);
    return key;
  } catch (_) {
    key.close();
    rethrow;
  }
}
