import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/validation.dart';

import 'mcp_credentials.dart';
import 'mcp_credential_file_probe.dart';
import 'paths.dart';
import 'security.dart';

Never _blocked() => throw StateError('STORAGE_BLOCKED');

/// Only the committed store can authorize writer calls. This layer never owns
/// Isar or a lease and never infers grants from filesystem contents.
final class McpCredentialFiles {
  McpCredentialFiles({
    required String localAppData,
    required this.workspaceId,
    required this.ownerSid,
    required this.custody,
  }) : localAppData = p.normalize(p.absolute(localAppData)) {
    try {
      requireUuid(workspaceId);
      if (ownerSid != currentUserSid()) _blocked();
      validateLocalPath(this.localAppData, directory);
    } catch (_) {
      _blocked();
    }
  }
  final String localAppData, workspaceId, ownerSid;
  final McpCredentialCustody custody;
  String get directory =>
      p.join(localAppData, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  String get _root => p.join(directory, 'mcp-credentials');

  Future<T> _safe<T>(
    Future<T> Function() body, {
    bool admission = false,
  }) async {
    try {
      return await body();
    } catch (e) {
      if (e is StateError &&
          {
            'INCOMPATIBLE',
            'FORBIDDEN',
            'STORAGE_BLOCKED',
            'RESOURCE_LIMIT',
          }.contains(e.message)) {
        if (!admission && e.message == 'RESOURCE_LIMIT') _blocked();
        rethrow;
      }
      if (admission &&
          e is FileSystemException &&
          e.message == 'RESOURCE_LIMIT') {
        throw StateError('RESOURCE_LIMIT');
      }
      _blocked();
    }
  }

  void _dir(String path) {
    requireSafePath(localAppData, path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
        FileSystemEntityType.directory)
      _blocked();
    requireOwnerOnlyFileAcl(path, ownerSid);
  }

  void _parents() {
    var path = localAppData;
    for (final name in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      path = p.join(path, name);
      _dir(path);
    }
  }

  String _grant(String id) {
    requireUuid(id);
    return p.join(_root, id);
  }

  void _binding(McpCredentialBinding binding) {
    if (binding.workspaceId != workspaceId || binding.ownerSid != ownerSid)
      _blocked();
  }

  String _blob(McpCredentialBinding binding) =>
      p.join(_grant(binding.grantId), '${binding.secretRef}.dpapi');
  String _lookup(String grantId) => p.join(_grant(grantId), 'current.json');

  Map<String, Object?> _document(McpCredentialBinding binding, bool revoked) =>
      {
        'format': 1,
        'product': 'serverdeck-next-mcp-lookup',
        'workspaceId': workspaceId,
        'grantId': binding.grantId,
        'secretRef': binding.secretRef,
        'ownerSid': ownerSid,
        'issuedAt': binding.issuedAt,
        'revoked': revoked,
      };

  Future<_Lookup> _readLookup(String grantId) async {
    _parents();
    _dir(_root);
    _dir(_grant(grantId));
    final bytes = await readProtectedFile(
      localAppData,
      _lookup(grantId),
      ownerSid,
      maxBytes: 4096,
    );
    final value = StrictCodec().decode(bytes, maxBytes: 4096);
    requireFields(value, {
      'format',
      'product',
      'workspaceId',
      'grantId',
      'secretRef',
      'ownerSid',
      'issuedAt',
      'revoked',
    });
    if (value['format'] is! int) _blocked();
    if (value['format'] != 1) throw StateError('INCOMPATIBLE');
    if (value['product'] != 'serverdeck-next-mcp-lookup' ||
        value['workspaceId'] != workspaceId ||
        value['grantId'] != grantId ||
        value['ownerSid'] != ownerSid ||
        value['revoked'] is! bool ||
        value['secretRef'] is! String ||
        value['issuedAt'] is! String)
      _blocked();
    final binding = McpCredentialBinding(
      workspaceId: workspaceId,
      grantId: grantId,
      ownerSid: ownerSid,
      secretRef: value['secretRef'] as String,
      issuedAt: value['issuedAt'] as String,
    );
    return _Lookup(binding, value['revoked'] as bool);
  }

  Future<McpClientKey> _open(McpCredentialBinding binding) async {
    _binding(binding);
    _parents();
    _dir(_root);
    _dir(_grant(binding.grantId));
    return custody.open(
      await readProtectedFile(
        localAppData,
        _blob(binding),
        ownerSid,
        maxBytes: 16384,
      ),
      binding,
    );
  }

  /// Validates retained blobs, including revoked metadata, without authenticating.
  Future<McpClientKey> openReferenced(McpCredentialBinding binding) =>
      _safe(() => _open(binding));

  /// Read-only startup preflight, including an empty workspace with orphan data.
  Future<void> validateInventory() => _safe(() => _budget());

  /// Missing lookup is permitted only within an existing protected grant tree.
  /// Unlike the bridge path this can inspect revoked/stale metadata, not keys.
  Future<McpRecoveryLookup?> readLookupForRecovery(String grantId) =>
      _safe(() async {
        _parents();
        _dir(_root);
        _dir(_grant(grantId));
        final target = _lookup(grantId);
        if (FileSystemEntity.typeSync(target, followLinks: false) ==
            FileSystemEntityType.notFound)
          return null;
        final current = await _readLookup(grantId);
        return McpRecoveryLookup._(current.binding, current.revoked);
      });

  /// A bridge read never initializes a directory or reconciles a stale pointer.
  Future<McpLoadedCredential> readForBridge(String grantId) => _safe(() async {
    final lookup = await _readLookup(grantId);
    if (lookup.revoked) throw StateError('FORBIDDEN');
    return McpLoadedCredential._(lookup.binding, await _open(lookup.binding));
  });

  /// Caller retains sole-writer serialization through subsequent DB commit and
  /// publish. Failed stages/transactions leave inert files, never a lookup.
  Future<void> stage(McpCredentialBinding binding) => _safe(() async {
    _binding(binding);
    _parents();
    final folder = _grant(binding.grantId);
    final exists =
        FileSystemEntity.typeSync(folder, followLinks: false) !=
        FileSystemEntityType.notFound;
    if (exists) _dir(folder);
    final created = await custody.create(binding);
    try {
      await _budget(
        files: 2,
        directories: exists ? 0 : 1,
        bytes: created.wrapper.length + 4096,
      );
      await requireProtectedDiskSpace(
        localAppData,
        directory,
        ownerSid,
        minimumBytes: mcpCredentialFileProbesEnabled
            ? McpCredentialFileProbe.minimumBytes(128 * 1024)
            : 128 * 1024,
      );
      createProtectedDirectory(localAppData, _root, ownerSid);
      createProtectedDirectory(localAppData, folder, ownerSid);
      await writeNewProtectedFile(
        localAppData,
        _blob(binding),
        ownerSid,
        created.wrapper,
      );
      final verified = await _open(binding);
      verified.close();
    } finally {
      created.key.close();
    }
  }, admission: true);

  /// Publish ONLY the current committed binding. Callers validate every retained
  /// grant before the first startup publish; this single-file primitive cannot.
  Future<void> publish(
    McpCredentialBinding binding, {
    required bool revoked,
  }) => _safe(() async {
    _binding(binding);
    _parents();
    _dir(_root);
    _dir(_grant(binding.grantId));
    final key = await _open(binding);
    key.close();
    final target = _lookup(binding.grantId);
    final expected = StrictCodec().encode(
      _document(binding, revoked),
      maxBytes: 4096,
    );
    final exists =
        FileSystemEntity.typeSync(target, followLinks: false) !=
        FileSystemEntityType.notFound;
    if (exists) {
      final current = await _readLookup(binding.grantId);
      if (current.binding.secretRef == binding.secretRef &&
          current.binding.issuedAt == binding.issuedAt &&
          current.revoked == revoked) {
        await _budget();
        return;
      }
    }
    await _budget(files: 1, bytes: expected.length);
    await requireProtectedDiskSpace(
      localAppData,
      directory,
      ownerSid,
      minimumBytes: mcpCredentialFileProbesEnabled
          ? McpCredentialFileProbe.minimumBytes(128 * 1024)
          : 128 * 1024,
    );
    final random = Random.secure();
    final suffix = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final temporary = '$target.$suffix.pending';
    await writeNewProtectedFile(localAppData, temporary, ownerSid, expected);
    if (mcpCredentialFileProbesEnabled)
      await McpCredentialFileProbe.hit(McpLookupWriteBoundary.afterPending);
    await promoteProtectedPath(
      localAppData,
      temporary,
      target,
      ownerSid,
      replace: true,
    );
    if (mcpCredentialFileProbesEnabled)
      await McpCredentialFileProbe.hit(McpLookupWriteBoundary.afterRename);
    final actual = await readProtectedFile(
      localAppData,
      target,
      ownerSid,
      maxBytes: 4096,
    );
    if (mcpCredentialFileProbesEnabled)
      await McpCredentialFileProbe.hit(McpLookupWriteBoundary.afterReadback);
    if (actual.length != expected.length) _blocked();
    for (var i = 0; i < expected.length; i++) {
      if (actual[i] != expected[i]) _blocked();
    }
  });

  /// Bounded fixed-depth enumeration; no eager recursive file list or decryption
  /// of orphans. Headroom is protected by the caller's common mutation lease.
  Future<void> _budget({
    int files = 0,
    int directories = 0,
    int bytes = 0,
  }) async {
    _parents();
    void limit() {
      if (files > 4096 || directories > 4096 || bytes > 32 * 1024 * 1024) {
        throw StateError('RESOURCE_LIMIT');
      }
    }

    limit();
    if (FileSystemEntity.typeSync(_root, followLinks: false) ==
        FileSystemEntityType.notFound)
      return;
    _dir(_root);
    await for (final folder in Directory(_root).list(followLinks: false)) {
      requireUuid(p.basename(folder.path));
      _dir(folder.path);
      directories++;
      limit();
      await for (final file in Directory(
        folder.path,
      ).list(followLinks: false)) {
        requireSafePath(localAppData, file.path);
        if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
            FileSystemEntityType.file)
          _blocked();
        requireOwnerOnlyFileAcl(file.path, ownerSid);
        final name = p.basename(file.path);
        final blob = name.endsWith('.dpapi');
        if (blob) {
          requireUuid(name.substring(0, name.length - 6));
        } else if (name != 'current.json' &&
            !RegExp(r'^current\.json\.[a-f0-9]{32}\.pending$').hasMatch(name)) {
          _blocked();
        }
        final size = File(file.path).lengthSync();
        if (size > (blob ? 16384 : 4096)) _blocked();
        files++;
        bytes += size;
        limit();
      }
    }
  }
}

final class _Lookup {
  const _Lookup(this.binding, this.revoked);
  final McpCredentialBinding binding;
  final bool revoked;
}

final class McpLoadedCredential {
  const McpLoadedCredential._(this.binding, this.key);
  final McpCredentialBinding binding;
  final McpClientKey key;
}

final class McpRecoveryLookup {
  const McpRecoveryLookup._(this.binding, this.revoked);
  final McpCredentialBinding binding;
  final bool revoked;
}
