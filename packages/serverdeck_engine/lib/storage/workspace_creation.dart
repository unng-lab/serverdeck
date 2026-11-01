part of 'workspace.dart';

/// Sole target3 creation/open owner. No server service/SSH is started here.
Future<Workspace> _openWorkspace({
  required ProtectedFiles files,
  required NativeStoreRuntime runtime,
  required WorkspaceLease lease,
  required KeyCustody custody,
  void Function()? checkStartup,
}) async {
  final localAppData = files.root;
  if (Workspace.hasOpenReservation || Isar.getInstance('workspace') != null)
    throw StateError('STORAGE_BLOCKED');
  Workspace._reserved = true;
  ReceiptKeyMaterial? key;
  StateStore? store;
  Isar? database;
  WorkspaceSnapshot? stagePreflight;
  var transferred = false, closed = true, openingStage = false;
  void owner() {
    checkStartup?.call();
    files.requirePath(files.root);
    if (files.root != localAppData ||
        !p.isAbsolute(localAppData) ||
        p.normalize(localAppData) != localAppData)
      throw StateError('STORAGE_BLOCKED');
    if (!lease.isHeld ||
        custody.ownerSid != files.ownerIdentity ||
        lease.ownerIdentity != custody.ownerSid ||
        lease.workspaceSlot != 'default')
      throw StateError('STORAGE_BLOCKED');
  }

  final parent = p.join(localAppData, 'ServerDeckNext', 'v1', 'workspaces');
  final active = p.join(parent, 'default'),
      stage = p.join(parent, 'default.creating');
  try {
    owner();
    await runtime.initialize();
    owner();
    await runtime.revalidate();
    owner();
    for (final path in [
      p.join(localAppData, 'ServerDeckNext'),
      p.join(localAppData, 'ServerDeckNext', 'v1'),
      parent,
    ]) {
      files.createDirectory(path);
      owner();
    }
    files.requirePath(active);
    files.requirePath(stage);
    final activeType = files.kind(active);
    final stageType = files.kind(stage);
    if ((activeType != ProtectedPathKind.absent &&
            activeType != ProtectedPathKind.directory) ||
        (stageType != ProtectedPathKind.absent &&
            stageType != ProtectedPathKind.directory) ||
        (activeType != ProtectedPathKind.absent &&
            stageType != ProtectedPathKind.absent))
      throw StateError('STORAGE_BLOCKED');
    if (activeType == ProtectedPathKind.directory) {
      final manifest = StrictCodec().decode(
        await files.readFile(
          p.join(active, 'workspace.manifest.json'),
          maxBytes: 4096,
        ),
        maxBytes: 4096,
      );
      var residue = false;
      for (final suffix in ['.upgrading-1-2', '.upgrading-2-3']) {
        final path = '$active$suffix';
        files.requirePath(path);
        residue |= files.kind(path) != ProtectedPathKind.absent;
      }
      // Only the target format is supported. Never upgrade or rewrite legacy
      // data, including a partially completed upgrade left by another version.
      if (manifest['format'] != 3 || manifest['schema'] != 3 || residue) {
        throw StateError('INCOMPATIBLE');
      }
      owner();
      key = await _workspaceKey(files, active, custody);
      owner();
    } else {
      for (final suffix in ['.upgrading-1-2', '.upgrading-2-3']) {
        final residue = '$active$suffix';
        files.requirePath(residue);
        if (files.kind(residue) != ProtectedPathKind.absent)
          throw StateError('STORAGE_BLOCKED');
      }
      if (stageType == ProtectedPathKind.absent) {
        files.createDirectory(stage);
        key = await custody.createReceiptKey(
          Workspace._uuid(),
          Workspace._uuid(),
        );
        owner();
        await files.writeNewFile(
          p.join(stage, 'receipt-key.dpapi'),
          key.wrapper,
        );
        owner();
        final manifest = await custody.createWorkspaceManifest(key);
        owner();
        await files.writeNewFile(
          p.join(stage, 'workspace.manifest.json'),
          StrictCodec().encode(manifest, maxBytes: 4096),
        );
        owner();
        for (final name in ['workspace.isar', 'workspace.isar-lck']) {
          owner();
          await files.createEmptyFile(p.join(stage, name));
        }
        await _creationInventory(files, stage);
        owner();
        await runtime.revalidate();
        owner();
        openingStage = true;
        closed = false;
        database = await Isar.open(
          workspaceSchemas,
          directory: stage,
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
        final creating = database;
        await runtime.revalidate();
        owner();
        await creating.writeTxn(() async {
          owner();
          await creating.storedWorkspaces.put(rows.workspace);
          owner();
          await creating.storedSettings.put(rows.settings);
          owner();
        });
      } else {
        await _creationInventory(files, stage);
        owner();
        key = await _workspaceKey(files, stage, custody);
        owner();
        stagePreflight = await readInitialWorkspace(
          NativeWorkspaceRows.fromSnapshot(
            Uint8List.fromList(
              await files.readFile(
                p.join(stage, 'workspace.isar'),
                maxBytes: 64 * 1024 * 1024,
              ),
            ),
            directory: stage,
          ),
          key,
          custody,
          localAppData: localAppData,
          lease: lease,
          protectedFiles: files,
        );
        owner();
        await runtime.revalidate();
        owner();
        openingStage = true;
        closed = false;
        database = await Isar.open(
          workspaceSchemas,
          directory: stage,
          name: 'workspace',
          maxSizeMiB: 64,
          relaxedDurability: false,
          inspector: false,
        );
      }
      owner();
      final reopened = await readInitialWorkspace(
        IsarRowSource(database),
        key,
        custody,
        localAppData: localAppData,
        lease: lease,
        protectedFiles: files,
      );
      owner();
      if (stagePreflight != null)
        requireSameWorkspaceRows(stagePreflight, reopened);
      if (!await database.close()) throw StateError('STORAGE_BLOCKED');
      database = null;
      openingStage = false;
      closed = true;
      await _creationInventory(files, stage);
      owner();
      await runtime.revalidate();
      owner();
      await files.promotePath(stage, active);
      owner();
    }
    owner();
    Workspace._reserved = false;
    store = await StateStore.open(
      files: files,
      runtime: runtime,
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
    if (StateStore.hasOpenReservation) closed = false;
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

Future<void> _creationInventory(ProtectedFiles files, String stage) async {
  files.requirePath(stage);
  files.requireOwnerOnly(stage);
  final names = <String>{};
  await for (final entry in files.children(stage)) {
    final name = p.basename(entry);
    if (!const {
          'workspace.isar',
          'workspace.isar-lck',
          'receipt-key.dpapi',
          'workspace.manifest.json',
        }.contains(name) ||
        !names.add(name) ||
        names.length > 4 ||
        files.kind(entry) != ProtectedPathKind.file)
      throw StateError('STORAGE_BLOCKED');
    files.requirePath(entry);
    files.requireOwnerOnly(entry);
  }
  if (names.length != 4) throw StateError('STORAGE_BLOCKED');
}

Future<ReceiptKeyMaterial> _workspaceKey(
  ProtectedFiles files,
  String directory,
  KeyCustody custody,
) async {
  files.requirePath(directory);
  files.requireOwnerOnly(directory);
  final manifest = StrictCodec().decode(
    await files.readFile(
      p.join(directory, 'workspace.manifest.json'),
      maxBytes: 4096,
    ),
    maxBytes: 4096,
  );
  final parsed = WorkspaceManifest.fromJson(manifest);
  if (parsed.ownerSid != custody.ownerSid) throw StateError('STORAGE_BLOCKED');
  final key = await custody.openReceiptKey(
    await files.readFile(
      p.join(directory, 'receipt-key.dpapi'),
      maxBytes: 16384,
    ),
    parsed.workspaceId,
    parsed.receiptKeyId,
  );
  try {
    await custody.verifyWorkspaceManifest(manifest, key);
    return key;
  } catch (_) {
    key.close();
    rethrow;
  }
}
