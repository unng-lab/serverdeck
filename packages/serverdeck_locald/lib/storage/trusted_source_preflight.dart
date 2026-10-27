part of 'workspace_migration.dart';

/// No public arbitrary directory, alternate writer or credentials owner. The
/// full migration controller reuses this component within its held reservation.
final class _TrustedSourcePreflight {
  _TrustedSourcePreflight(
    String localAppData,
    this.lease,
    this.custody,
    this.key,
  ) : root = p.normalize(p.absolute(localAppData));
  final String root;
  final MutexLease lease;
  final KeyCustody custody;
  final ReceiptKeyMaterial key;
  String get sid => custody.ownerSid;
  String get active =>
      p.join(root, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  bool nativeClosed = true;

  void owner() {
    if (!lease.isHeld || sid != currentUserSid() || key.ownerSid != sid)
      _blocked();
  }

  Future<void> live() async {
    owner();
    await custody.createWorkspaceManifest(key);
    owner();
  }

  void protected(String path, FileSystemEntityType type) {
    owner();
    requireSafePath(root, path);
    if (FileSystemEntity.typeSync(path, followLinks: false) != type) _blocked();
    requireOwnerOnlyFileAcl(path, sid);
  }

  Future<void> settled() async {
    owner();
    for (final suffix in ['.creating', '.upgrading-1-2', '.upgrading-2-3']) {
      final stage = '$active$suffix';
      requireSafePath(root, stage);
      final type = FileSystemEntity.typeSync(stage, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (suffix != '.upgrading-2-3' || type != FileSystemEntityType.directory)
        _blocked();
      requireOwnerOnlyFileAcl(stage, sid);
      if (!await Directory(stage).list(followLinks: false).isEmpty) _blocked();
      owner();
    }
  }

  Future<List<int>> bytes(String name, int maximum) async {
    await live();
    final value = await readProtectedFile(
      root,
      p.join(active, name),
      sid,
      maxBytes: maximum,
    );
    await live();
    return value;
  }

  Future<UpgradeSnapshot> run() async {
    await live();
    var directory = root;
    for (final name in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      directory = p.join(directory, name);
      protected(directory, FileSystemEntityType.directory);
    }
    await settled();
    final manifestBytes = await bytes('workspace.manifest.json', 4096);
    final manifest = MigrationManifest.fromJson(
      StrictCodec().decode(manifestBytes, maxBytes: 4096),
    );
    if (manifest.schema != 2) throw StateError('INCOMPATIBLE');
    if (manifest.workspaceId != key.workspaceId ||
        manifest.receiptKeyId != key.receiptKeyId ||
        manifest.ownerSid != sid)
      _blocked();
    final wrapper = await bytes('receipt-key.dpapi', 16384);
    if (!_same(wrapper, key.wrapper)) _blocked();
    final snapshot = await bytes('workspace.isar', 64 << 20);
    if (inspectNativeWorkspaceSchema(Uint8List.fromList(snapshot)) != 2)
      throw StateError('INCOMPATIBLE');
    protected(p.join(active, 'workspace.isar-lck'), FileSystemEntityType.file);
    await live();
    await settled();
    if (Isar.getInstance('workspace') != null) _blocked();
    Isar? opened;
    nativeClosed = false;
    try {
      opened = await Isar.open(
        automationWorkspaceSchemas,
        directory: active,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      await live();
      await settled();
      final result = await readSchema2UpgradePreflight(
        opened,
        key,
        custody,
        localAppData: root,
        lease: lease,
      );
      await live();
      await settled();
      // The inspected identity must not drift during asynchronous DPAPI work.
      if (!_same(await bytes('workspace.manifest.json', 4096), manifestBytes) ||
          !_same(await bytes('receipt-key.dpapi', 16384), wrapper))
        _blocked();
      return result;
    } finally {
      final registered = Isar.getInstance('workspace');
      final candidate =
          opened ??
          (registered != null &&
                  registered.directory != null &&
                  p.equals(
                    p.normalize(p.absolute(registered.directory!)),
                    active,
                  )
              ? registered
              : null);
      if (candidate != null) {
        nativeClosed = await confirmNativeClose(
          migrationProbesEnabled
              ? () => MigrationProbe.closeNative(candidate.close)
              : candidate.close,
        );
      }
      // No instance after a throwing open is not proof of native cleanup.
      if (!nativeClosed) _blocked();
    }
  }

  bool _same(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
