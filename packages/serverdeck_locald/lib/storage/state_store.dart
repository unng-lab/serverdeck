import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import '../bootstrap/native_runtime.dart';
import '../automation/snapshot.dart';
import '../automation/profile_commands.dart';
import '../mcp/grants.dart';
import 'credential_validation.dart';
import 'automation_records.dart';
import 'foundation_snapshot.dart';
import 'grant_write_probe.dart';
import 'host_trust_records.dart';
import 'host_trust_models.dart';
import 'migration_rows.dart';
import 'key_custody.dart';
import 'migration_journal.dart';
import 'models.dart';
import 'native_failure.dart';
import 'native_close.dart';
import 'native_schema.dart';
import 'records.dart';
import 'trusted_snapshot.dart';
import 'workspace_migration.dart';
import 'workspace.dart';

part 'owner_grant_writes.dart';
part 'mcp_grant_reads.dart';
part 'operational_foundation_writes.dart';
part 'trusted_foundation_writes.dart';
part 'automation_profile_writes.dart';

/// Owned existing-workspace repository. Creation/promotion belongs to workspace.
class StateStore {
  static bool _reserved = false;
  static bool get hasOpenReservation => _reserved;
  StateStore._(
    this._isar,
    this._lease,
    this._custody,
    this._receiptKey,
    this._state, [
    this._operational,
    this._operationalRoot,
    this._trustedOperational,
  ]);
  final Isar _isar;
  final MutexLease _lease;
  final KeyCustody _custody;
  final ReceiptKeyMaterial _receiptKey;
  WorkspaceState _state;
  OperationalSnapshot? _operational;
  TrustedOperationalSnapshot? _trustedOperational;
  final String? _operationalRoot;
  bool _authorityUnavailableValue = false;
  Completer<void>? _authorityPublication;
  bool get _authorityUnavailable => _authorityUnavailableValue;
  set _authorityUnavailable(bool value) {
    if (value == _authorityUnavailableValue) return;
    _authorityUnavailableValue = value;
    if (value) {
      _authorityPublication = Completer<void>();
    } else {
      _settleAuthorityPublication();
    }
  }

  void _settleAuthorityPublication() {
    final pending = _authorityPublication;
    _authorityPublication = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Classification only: never a permission or a cached grant fallback.
  bool get hasPendingMcpAuthorityPublication =>
      _authorityUnavailable &&
      _authorityPublication != null &&
      !_blocked &&
      !_closing &&
      !_closed &&
      _lease.isHeld;

  Future<void> waitForMcpAuthority({required Duration deadline}) async {
    final watch = Stopwatch()..start();
    while (true) {
      _ensure();
      final remaining = deadline - watch.elapsed;
      if (remaining <= Duration.zero) throw StateError('TIMEOUT');
      if (!_authorityUnavailable) return;
      final pending = _authorityPublication;
      if (pending == null) throw StateError('STORAGE_BLOCKED');
      try {
        await pending.future.timeout(remaining);
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
    }
  }

  final _pendingAutomation = <String, _AutomationPending>{};
  int _pendingFoundation = 0;
  final _grantPublished = <void Function(String, int)>{};

  /// Trusted same-isolate lifecycle subscription, never a wire operation.
  void Function() onMcpGrantPublished(void Function(String, int) listener) {
    _ensure();
    _grantPublished.add(listener);
    return () => _grantPublished.remove(listener);
  }

  bool get isAutomationReady =>
      !_blocked &&
      !_closing &&
      !_closed &&
      !_authorityUnavailable &&
      _operational != null &&
      _lease.isHeld;

  /// Internal retained schema3 snapshot only; service/writer readiness is a
  /// separate gate. Existing schema2 services cannot consume this store.
  bool get isTrustedSnapshotLoaded =>
      !_blocked &&
      !_closing &&
      !_closed &&
      !_authorityUnavailable &&
      _trustedOperational != null &&
      _lease.isHeld;
  Future<void> _tail = Future.value();
  Future<void>? _closeOperation;
  bool _blockedValue = false, _closing = false, _closed = false;
  bool get _blocked => _blockedValue;
  set _blocked(bool value) {
    _blockedValue = value;
    if (value) _settleAuthorityPublication();
  }

  /// Trusted internal authority read; never exported by Local API or MCP.
  ClientGrantRecord currentMcpGrant(String id, {required DateTime at}) =>
      _currentMcpGrant(id, at: at);

  Future<McpGrantKey> openMcpGrantKey(
    String id, {
    required DateTime Function() clock,
    Duration? publicationDeadline,
  }) => _openMcpGrantKey(
    id,
    clock: clock,
    publicationDeadline: publicationDeadline,
  );

  /// Internal existing-schema2 opener. Product bootstrap/1.1 activation and
  /// mutation admission are separate gates; this neither initializes nor migrates.
  static Future<StateStore> openOperational({
    required String localAppData,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
  }) => _openOperational(
    localAppData: localAppData,
    appRoot: appRoot,
    lease: lease,
    custody: custody,
    receiptKey: receiptKey,
    mcpBundle: false,
  );

  /// Explicit existing-schema2 opener for the verified API1.1 locald image.
  /// Does not create/migrate a workspace or select the product bootstrap mode.
  static Future<StateStore> openMcpOperational({
    required String localAppData,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
  }) => _openOperational(
    localAppData: localAppData,
    appRoot: appRoot,
    lease: lease,
    custody: custody,
    receiptKey: receiptKey,
    mcpBundle: true,
  );

  /// Explicit existing-schema3 composition for the actual format3 locald.
  /// Never creates, migrates or activates a workspace or remote service.
  static Future<StateStore> openTrustedOperational({
    required String localAppData,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
  }) => _openOperational(
    localAppData: localAppData,
    appRoot: appRoot,
    lease: lease,
    custody: custody,
    receiptKey: receiptKey,
    mcpBundle: true,
    trusted: true,
  );

  static Future<StateStore> _openOperational({
    required String localAppData,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
    required bool mcpBundle,
    bool trusted = false,
  }) async {
    if (Workspace.hasOpenReservation ||
        Isar.getInstance('workspace') != null ||
        !lease.isHeld ||
        custody.ownerSid != currentUserSid()) {
      throw StateError('STORAGE_BLOCKED');
    }
    _reserved = true;
    Isar? isar;
    String? openedDirectory;
    var transferred = false, safeToRelease = true, runtimeChecked = false;
    void owner() {
      if (!lease.isHeld ||
          custody.ownerSid != currentUserSid() ||
          receiptKey.ownerSid != custody.ownerSid) {
        throw StateError('STORAGE_BLOCKED');
      }
    }

    Future<void> live() async {
      owner();
      if (trusted) {
        await custody.createTrustedWorkspaceManifest(receiptKey);
      } else {
        await custody.createWorkspaceManifest(receiptKey);
      }
      owner();
    }

    try {
      if (trusted) {
        await initializeTrustedNativeRuntime(appRoot);
      } else if (mcpBundle) {
        await initializeMcpNativeRuntime(appRoot);
      }
      runtimeChecked = true;
      await live();
      if (!mcpBundle) await initializeNativeRuntime(appRoot);
      await live();
      var directory = p.normalize(p.absolute(localAppData));
      for (final segment in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
        directory = p.join(directory, segment);
        requireSafePath(localAppData, directory);
        if (FileSystemEntity.typeSync(directory, followLinks: false) !=
            FileSystemEntityType.directory)
          throw StateError('STORAGE_BLOCKED');
        requireOwnerOnlyFileAcl(directory, custody.ownerSid);
      }
      void settled() {
        owner();
        for (final suffix in [
          '.creating',
          '.upgrading-1-2',
          if (trusted) '.upgrading-2-3',
        ]) {
          final stage = '$directory$suffix';
          requireSafePath(localAppData, stage);
          if (FileSystemEntity.typeSync(stage, followLinks: false) !=
              FileSystemEntityType.notFound)
            throw StateError('STORAGE_BLOCKED');
        }
      }

      settled();
      final manifestDocument = StrictCodec().decode(
        await readProtectedFile(
          localAppData,
          p.join(directory, 'workspace.manifest.json'),
          custody.ownerSid,
          maxBytes: 4096,
        ),
        maxBytes: 4096,
      );
      await live();
      if (trusted) {
        await custody.verifyTrustedWorkspaceManifest(
          manifestDocument,
          receiptKey,
        );
      } else {
        final manifest = MigrationManifest.fromJson(manifestDocument);
        if (manifest.schema != 2) throw StateError('INCOMPATIBLE');
        if (manifest.workspaceId != receiptKey.workspaceId ||
            manifest.receiptKeyId != receiptKey.receiptKeyId ||
            manifest.ownerSid != receiptKey.ownerSid)
          throw StateError('STORAGE_BLOCKED');
      }
      final wrapper = await readProtectedFile(
        localAppData,
        p.join(directory, 'receipt-key.dpapi'),
        custody.ownerSid,
        maxBytes: 16384,
      );
      await live();
      if (!_equal(wrapper, receiptKey.wrapper))
        throw StateError('STORAGE_BLOCKED');
      final bytes = await readProtectedFile(
        localAppData,
        p.join(directory, 'workspace.isar'),
        custody.ownerSid,
        maxBytes: 64 << 20,
      );
      await live();
      final schema = trusted
          ? inspectTrustedNativeWorkspaceSchema(Uint8List.fromList(bytes))
          : inspectNativeWorkspaceSchema(Uint8List.fromList(bytes));
      if (schema != (trusted ? 3 : 2)) throw StateError('INCOMPATIBLE');
      final lock = p.join(directory, 'workspace.isar-lck');
      requireSafePath(localAppData, lock);
      if (FileSystemEntity.typeSync(lock, followLinks: false) !=
          FileSystemEntityType.file)
        throw StateError('STORAGE_BLOCKED');
      requireOwnerOnlyFileAcl(lock, custody.ownerSid);
      await live();
      settled();
      if (Isar.getInstance('workspace') != null)
        throw StateError('STORAGE_BLOCKED');
      // An exception before returning an instance cannot prove native ownership
      // ended. Retain reservation until a confirmed close, including this gap.
      safeToRelease = false;
      openedDirectory = directory;
      isar = await Isar.open(
        trusted ? trustedWorkspaceSchemas : automationWorkspaceSchemas,
        directory: directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      await live();
      if (trusted) {
        final snapshot = await readTrustedOperationalSnapshot(
          isar,
          receiptKey,
          custody,
          localAppData: localAppData,
          lease: lease,
        );
        await live();
        transferred = true;
        return StateStore._(
          isar,
          lease,
          custody,
          receiptKey,
          snapshot.foundation.foundation,
          null,
          localAppData,
          snapshot,
        );
      }
      final snapshot = await readOperationalSnapshot(
        isar,
        receiptKey,
        custody,
        localAppData: localAppData,
        lease: lease,
      );
      await live();
      transferred = true;
      return StateStore._(
        isar,
        lease,
        custody,
        receiptKey,
        snapshot.foundation.state,
        snapshot,
        localAppData,
      );
    } catch (error) {
      // A throwing open may have registered its own instance before returning.
      // Close only that attributable instance, never a preexisting foreign one.
      final registered = !safeToRelease ? Isar.getInstance('workspace') : null;
      final candidate =
          isar ??
          (registered != null &&
                  openedDirectory != null &&
                  registered.directory != null &&
                  p.equals(p.normalize(registered.directory!), openedDirectory)
              ? registered
              : null);
      if (candidate != null)
        safeToRelease = await confirmNativeClose(candidate.close);
      if (error is StateError &&
          (error.message == 'INCOMPATIBLE' ||
              error.message == 'PREREQUISITE_UNAVAILABLE' ||
              mcpBundle && !runtimeChecked && error.message == 'UNAUTHORIZED'))
        rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      if (!transferred && safeToRelease) _reserved = false;
    }
  }

  OperationalSnapshot get operational {
    _ensure();
    if (_authorityUnavailable) throw StateError('STORAGE_BLOCKED');
    final value = _operational;
    if (value == null) throw StateError('STORAGE_BLOCKED');
    return value;
  }

  TrustedOperationalSnapshot get trustedOperational {
    _ensure();
    if (_authorityUnavailable) throw StateError('STORAGE_BLOCKED');
    final value = _trustedOperational;
    if (value == null) throw StateError('STORAGE_BLOCKED');
    return value;
  }

  Future<Map<String, Object?>> mutateOwnerGrant(
    OwnerGrantCommand command, {
    required DateTime Function() clock,
  }) {
    try {
      if (_closing) throw StateError('NOT_READY');
      _ensure();
      if (_operational == null || _operationalRoot == null)
        throw StateError('STORAGE_BLOCKED');
      final mac = base64.decode(
        _custody.receiptDigestSync(_receiptKey, command.canonicalRequest),
      );
      final digest = mac.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final existing = _pendingAutomation[command.requestId];
      if (existing != null) {
        if (existing.originGrantId != null) throw StateError('FORBIDDEN');
        if (existing.digest != digest) throw StateError('IDEMPOTENCY_CONFLICT');
        return existing.result.future;
      }
      if (_pendingAutomation.length + _pendingFoundation >= 32)
        throw StateError('RESOURCE_LIMIT');
      final pending = _AutomationPending(digest);
      _pendingAutomation[command.requestId] = pending;
      final run = _tail.then((_) => _writeOwnerGrant(command, digest, clock));
      _tail = run.then<void>(
        (result) {
          _pendingAutomation.remove(command.requestId);
          pending.result.complete(result);
        },
        onError: (Object error, StackTrace stack) {
          _pendingAutomation.remove(command.requestId);
          final known =
              error is StateError &&
              {
                'NOT_READY',
                'FORBIDDEN',
                'REVISION_CONFLICT',
                'IDEMPOTENCY_CONFLICT',
                'RESOURCE_LIMIT',
                'STORAGE_BLOCKED',
              }.contains(error.message);
          if (!known || error.message == 'STORAGE_BLOCKED') _blocked = true;
          pending.result.completeError(
            StateError(known ? error.message : 'STORAGE_BLOCKED'),
            stack,
          );
        },
      );
      return pending.result.future;
    } on StateError catch (error) {
      if (_operational != null &&
          !{
            'NOT_READY',
            'FORBIDDEN',
            'IDEMPOTENCY_CONFLICT',
            'RESOURCE_LIMIT',
          }.contains(error.message)) {
        _blocked = true;
      }
      return Future.error(
        StateError(
          {
                'NOT_READY',
                'FORBIDDEN',
                'IDEMPOTENCY_CONFLICT',
                'RESOURCE_LIMIT',
                'STORAGE_BLOCKED',
              }.contains(error.message)
              ? error.message
              : 'STORAGE_BLOCKED',
        ),
      );
    } catch (_) {
      if (_operational != null) _blocked = true;
      return Future.error(StateError('STORAGE_BLOCKED'));
    }
  }

  static Future<StateStore> open({
    required String localAppData,
    required String directory,
    required String appRoot,
    required MutexLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
  }) async {
    if (_reserved ||
        WorkspaceMigration.hasOpenReservation ||
        !lease.isHeld ||
        custody.ownerSid != currentUserSid()) {
      throw StateError('STORAGE_BLOCKED');
    }
    // Isar registers only after its async native open: reserve synchronously.
    _reserved = true;
    Isar? isar;
    var transferred = false, safeToRelease = true;
    try {
      await initializeNativeRuntime(appRoot);
      requireSafePath(localAppData, directory);
      requireOwnerOnlyFileAcl(directory, custody.ownerSid);
      final codec = StrictCodec();
      final manifest = await readProtectedFile(
        localAppData,
        p.join(directory, 'workspace.manifest.json'),
        custody.ownerSid,
        maxBytes: 4096,
      );
      await custody.verifyWorkspaceManifest(
        codec.decode(manifest, maxBytes: 4096),
        receiptKey,
      );
      final keyBytes = await readProtectedFile(
        localAppData,
        p.join(directory, 'receipt-key.dpapi'),
        custody.ownerSid,
        maxBytes: 16384,
      );
      if (!_equal(keyBytes, receiptKey.wrapper))
        throw StateError('STORAGE_BLOCKED');
      final snapshot = await readProtectedFile(
        localAppData,
        p.join(directory, 'workspace.isar'),
        custody.ownerSid,
        maxBytes: 64 * 1024 * 1024,
      );
      validateNativeSnapshot(Uint8List.fromList(snapshot));
      requireSafePath(localAppData, p.join(directory, 'workspace.isar-lck'));
      requireOwnerOnlyFileAcl(
        p.join(directory, 'workspace.isar-lck'),
        custody.ownerSid,
      );
      if (!lease.isHeld || Isar.getInstance('workspace') != null)
        throw StateError('STORAGE_BLOCKED');
      isar = await Isar.open(
        workspaceSchemas,
        directory: directory,
        name: 'workspace',
        maxSizeMiB: 64,
        relaxedDurability: false,
        inspector: false,
      );
      final state = (await readFoundationSnapshot(
        isar,
        receiptKey,
        custody,
      )).state;
      if (!lease.isHeld) throw StateError('STORAGE_BLOCKED');
      transferred = true;
      return StateStore._(isar, lease, custody, receiptKey, state);
    } catch (error) {
      if (isar != null) {
        safeToRelease = await confirmNativeClose(isar.close);
      }
      if (error is StateError &&
          (error.message == 'INCOMPATIBLE' ||
              error.message == 'PREREQUISITE_UNAVAILABLE'))
        rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      if (!transferred && safeToRelease) _reserved = false;
    }
  }

  WorkspaceState get state {
    _ensure();
    return _state;
  }

  void _ensure() {
    if (_blocked || _closed || _closing || !_lease.isHeld)
      throw StateError('STORAGE_BLOCKED');
  }

  /// Serial durable primitive; upstream coordinator owns CAS/idempotency/grants.
  Future<void> commit(WorkspaceState next) {
    _ensure();
    if (_operational != null || _trustedOperational != null)
      throw StateError('STORAGE_BLOCKED');
    final result = _tail.then((_) => _commit(next));
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _commit(
    WorkspaceState next, {
    bool operationalFoundation = false,
  }) async {
    _ensure();
    final current = _state;
    final operational = operationalFoundation ? this.operational : null;
    if (operational != null &&
        next.storeRevision != nextRevision(current.storeRevision))
      throw StateError('REVISION_CONFLICT');
    if (next.workspaceId != current.workspaceId ||
        next.receiptKeyId != current.receiptKeyId ||
        next.ownerSid != current.ownerSid ||
        next.storeRevision != nextRevision(current.storeRevision) ||
        next.receipts.length != current.receipts.length + 1)
      throw StateError('STORAGE_BLOCKED');
    final codec = StrictCodec();
    for (final entry in current.receipts.entries) {
      final retained = next.receipts[entry.key];
      if (retained == null ||
          !_equal(
            codec.canonical(entry.value.toJson()),
            codec.canonical(retained.toJson()),
          )) {
        throw StateError('STORAGE_BLOCKED');
      }
    }
    if (operational != null)
      _guardFoundationIdentities(current, next, operational.automation);
    final rows = operational == null
        ? WorkspaceRecords.fromState(next)
        : WorkspaceRecords.fromOperationalState(next);
    var transactionStarted = false;
    try {
      await validateWorkspaceCredentials(next, _custody);
      if (operational != null)
        await AutomationSnapshot.load(
          foundation: next,
          collections: operational.rows,
        );
      final oldProfiles = {
        for (final row in await _isar.storedProfiles.where().findAll())
          row.entityId: row,
      };
      final oldCredentials = {
        for (final row in await _isar.storedCredentials.where().findAll())
          row.entityId: row,
      };
      final oldReceipts = {
        for (final row in await _isar.storedReceipts.where().findAll())
          row.entityId: row,
      };
      _ensure();
      await _isar.writeTxn(() async {
        transactionStarted = true;
        for (final row in oldProfiles.values) {
          if (!next.profiles.containsKey(row.entityId))
            await _isar.storedProfiles.delete(row.id);
        }
        for (final row in oldCredentials.values) {
          if (!next.credentials.containsKey(row.entityId))
            await _isar.storedCredentials.delete(row.id);
        }
        for (final row in rows.profiles) {
          final old = oldProfiles[row.entityId];
          if (old != null) row.id = old.id;
          if (old?.payload != row.payload &&
              await _isar.storedProfiles.put(row) < 1)
            throw StateError('RESOURCE_LIMIT');
        }
        for (final row in rows.credentials) {
          final old = oldCredentials[row.entityId];
          if (old != null) row.id = old.id;
          if (old?.payload != row.payload &&
              await _isar.storedCredentials.put(row) < 1)
            throw StateError('RESOURCE_LIMIT');
        }
        for (final row in rows.receipts) {
          if (!oldReceipts.containsKey(row.entityId) &&
              await _isar.storedReceipts.put(row) < 1)
            throw StateError('RESOURCE_LIMIT');
        }
        if (!_equal(
          codec.canonical(next.settings.toJson()),
          codec.canonical(current.settings.toJson()),
        ))
          await _isar.storedSettings.put(rows.settings);
        await _isar.storedWorkspaces.put(rows.workspace);
      });
      if (operational != null)
        _operational = await _verifyOperationalFoundation(next, operational);
      _state = next;
    } catch (error) {
      if (transactionStarted &&
          (isNativeCapacityFailure(error) ||
              (error is StateError && error.message == 'RESOURCE_LIMIT'))) {
        try {
          _ensure();
          final persisted = operational == null
              ? (await readFoundationSnapshot(
                  _isar,
                  _receiptKey,
                  _custody,
                )).state
              : (await _verifyOperationalFoundation(
                  current,
                  operational,
                )).foundation.state;
          if (!_equal(
            codec.canonical(persisted.toJson()),
            codec.canonical(current.toJson()),
          ))
            throw StateError('STORAGE_BLOCKED');
        } catch (_) {
          _blocked = true;
          throw StateError('STORAGE_BLOCKED');
        }
        // Native writeTxn has completed its abort; every persisted record was
        // reread and verified against the unchanged ready model.
        throw StateError('RESOURCE_LIMIT');
      }
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<void> close() => _closeOperation ??= _close();

  Future<void> _close() async {
    _closing = true;
    _settleAuthorityPublication();
    await _tail;
    try {
      if (!await _isar.close()) throw StateError('STORAGE_BLOCKED');
      _reserved = false;
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    } finally {
      _closed = true;
    }
  }
}

bool _equal(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
