import 'package:serverdeck_engine/storage/executor_enrollments.dart';
import 'package:serverdeck_engine/storage/row_plan.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/automation/direct_ssh_dispatch.dart';
import 'package:serverdeck_protocol/validation.dart';
import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:serverdeck_engine/credentials/mcp_credential_files.dart';
import 'package:serverdeck_engine/platform/ports.dart';

import 'package:serverdeck_engine/automation/snapshot.dart';
import 'package:serverdeck_engine/automation/profile_commands.dart';
import 'package:serverdeck_engine/automation/plan_commands.dart';
import 'package:serverdeck_engine/automation/authority_commands.dart';
import 'package:serverdeck_engine/automation/job_commands.dart';
import 'package:serverdeck_engine/automation/direct_dispatch_binding.dart';

import 'package:serverdeck_engine/mcp/grants.dart';

import 'package:serverdeck_engine/storage/credential_validation.dart';

import 'package:serverdeck_engine/storage/host_trust_models.dart';

import 'package:serverdeck_engine/storage/key_custody.dart';

import 'package:serverdeck_engine/storage/models.dart';

import 'package:serverdeck_engine/storage/native_close.dart';
import 'package:serverdeck_engine/storage/preflight.dart';
import 'package:serverdeck_engine/storage/records.dart';

import 'package:serverdeck_engine/storage/workspace_snapshot.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:serverdeck_engine/storage/isar_storage.dart';
import 'package:serverdeck_engine/storage/workspace_storage.dart';

import 'workspace.dart';

part 'owner_grant_writes.dart';
part 'mcp_grant_reads.dart';
part 'foundation_writes.dart';
part 'automation_profile_writes.dart';
part 'automation_plan_writes.dart';
part 'automation_delta.dart';
part 'automation_authority_writes.dart';
part 'automation_job_writes.dart';
part 'automation_job_progress.dart';
part 'direct_ssh_dispatch_writes.dart';
part 'automation_store_view.dart';
part 'executor_metadata_writes.dart';

/// Owned existing-workspace repository. Creation/promotion belongs to workspace.
class StateStore {
  static bool _reserved = false;
  static WorkspaceStorageOpen? _uncertainOpen;
  static bool get hasOpenReservation => _reserved || _uncertainOpen != null;
  StateStore._(
    this._storage,
    this._lease,
    this._custody,
    this._receiptKey,
    this._state,
    ProtectedFiles files,
    this._runtime,
    this._snapshot,
  ) : _files = files,
      _localAppData = files.root;
  final WorkspaceStorage _storage;
  final WorkspaceLease _lease;
  final KeyCustody _custody;
  final ReceiptKeyMaterial _receiptKey;
  late final ExecutorEnrollmentStore _enrollmentStore = ExecutorEnrollmentStore(
    files: _files,
    lease: _lease,
    custody: _custody,
    key: _receiptKey,
    requireReady: () {
      _ensure();
      snapshot;
    },
    onStorageBlocked: () {
      _blocked = true;
    },
  );

  WorkspaceState _state;
  WorkspaceSnapshot _snapshot;
  final ProtectedFiles _files;
  final NativeStoreRuntime _runtime;
  final String _localAppData;
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

  bool get isReady =>
      !_blocked &&
      !_closing &&
      !_closed &&
      !_authorityUnavailable &&
      _lease.isHeld;
  Future<void> _tail = Future.value();
  Future<void>? _closeOperation;
  bool _blockedValue = false, _closing = false, _closed = false;
  bool get _blocked => _blockedValue;
  set _blocked(bool value) {
    _blockedValue = value;
    if (value) _settleAuthorityPublication();
  }

  ClientGrantRecord currentMcpGrant(String id, {required DateTime at}) =>
      _currentMcpGrant(id, at: at);

  Future<Map<String, ExecutorEnrollment>> readExecutorEnrollments() =>
      _queueMetadata(_enrollmentStore.read);

  Future<McpGrantKey> openMcpGrantKey(
    String id, {
    required DateTime Function() clock,
    Duration? publicationDeadline,
  }) => _openMcpGrantKey(
    id,
    clock: clock,
    publicationDeadline: publicationDeadline,
  );

  static Future<StateStore> open({
    required ProtectedFiles files,
    required NativeStoreRuntime runtime,
    required WorkspaceLease lease,
    required KeyCustody custody,
    required ReceiptKeyMaterial receiptKey,
    WorkspaceStorageProvider storageProvider =
        const IsarWorkspaceStorageProvider(),
  }) async {
    final localAppData = files.root;
    if (Workspace.hasOpenReservation ||
        storageProvider.hasOpenInstance ||
        !lease.isHeld ||
        custody.ownerSid != files.ownerIdentity ||
        lease.ownerIdentity != custody.ownerSid ||
        lease.workspaceSlot != 'default') {
      throw StateError('STORAGE_BLOCKED');
    }
    _reserved = true;
    WorkspaceStorageOpen? attempt;
    var transferred = false, safeToRelease = true, runtimeChecked = false;
    void owner() {
      files.requirePath(localAppData);
      if (files.root != localAppData ||
          !p.isAbsolute(localAppData) ||
          p.normalize(localAppData) != localAppData)
        throw StateError('STORAGE_BLOCKED');
      if (!lease.isHeld ||
          custody.ownerSid != files.ownerIdentity ||
          lease.ownerIdentity != custody.ownerSid ||
          lease.workspaceSlot != 'default' ||
          receiptKey.ownerSid != custody.ownerSid) {
        throw StateError('STORAGE_BLOCKED');
      }
    }

    Future<void> live() async {
      owner();
      await runtime.revalidate();
      await custody.createWorkspaceManifest(receiptKey);
      owner();
    }

    try {
      await runtime.initialize();
      runtimeChecked = true;
      await live();
      var directory = p.normalize(p.absolute(localAppData));
      for (final segment in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
        directory = p.join(directory, segment);
        files.requirePath(directory);
        if (files.kind(directory) != ProtectedPathKind.directory)
          throw StateError('STORAGE_BLOCKED');
        files.requireOwnerOnly(directory);
      }
      void settled() {
        owner();
        for (final suffix in [
          '.creating',
          '.upgrading-1-2',
          '.upgrading-2-3',
        ]) {
          final stage = '$directory$suffix';
          files.requirePath(stage);
          if (files.kind(stage) != ProtectedPathKind.absent)
            throw StateError('STORAGE_BLOCKED');
        }
      }

      settled();
      final manifestDocument = StrictCodec().decode(
        await files.readFile(
          p.join(directory, 'workspace.manifest.json'),
          maxBytes: 4096,
        ),
        maxBytes: 4096,
      );
      await live();
      await custody.verifyWorkspaceManifest(manifestDocument, receiptKey);
      final wrapper = await files.readFile(
        p.join(directory, 'receipt-key.dpapi'),
        maxBytes: 16384,
      );
      await live();
      if (!_equal(wrapper, receiptKey.wrapper))
        throw StateError('STORAGE_BLOCKED');
      final bytes = await files.readFile(
        p.join(directory, 'workspace.isar'),
        maxBytes: 64 << 20,
      );
      await live();
      final preflight = await preflightWorkspaceRows(
        () => storageProvider.preflightRows(
          Uint8List.fromList(bytes),
          directory: directory,
        ),
        files: files,
        lease: lease,
        key: receiptKey,
        custody: custody,
      );
      await live();
      final lock = p.join(directory, 'workspace.isar-lck');
      files.requirePath(lock);
      if (files.kind(lock) != ProtectedPathKind.file)
        throw StateError('STORAGE_BLOCKED');
      files.requireOwnerOnly(lock);
      await live();
      settled();
      if (storageProvider.hasOpenInstance) throw StateError('STORAGE_BLOCKED');
      // An exception before returning an instance cannot prove native ownership
      // ended. Retain reservation until a confirmed close, including this gap.
      attempt = storageProvider.createOpenAttempt(directory: directory);
      safeToRelease = false;
      final storage = await attempt.open();
      await live();
      final snapshot = await inspectWorkspaceSnapshot(
        storage,
        receiptKey,
        custody,
        localAppData: localAppData,
        lease: lease,
        protectedFiles: files,
      );
      await live();
      requireSameWorkspaceRows(preflight, snapshot);
      await recoverWorkspaceLookups(
        snapshot,
        files: files,
        lease: lease,
        key: receiptKey,
        custody: custody,
      );
      await live();
      transferred = true;
      return StateStore._(
        storage,
        lease,
        custody,
        receiptKey,
        snapshot.foundation.foundation,
        files,
        runtime,
        snapshot,
      );
    } catch (error) {
      // The attempt owns attributable cleanup, including a throwing native open.
      if (attempt != null) {
        safeToRelease = await confirmNativeClose(
          attempt.cleanupAfterFailedOpen,
        );
        if (!safeToRelease) _uncertainOpen = attempt;
      }
      if (error is StateError &&
          (error.message == 'INCOMPATIBLE' ||
              error.message == 'PREREQUISITE_UNAVAILABLE' ||
              !runtimeChecked && error.message == 'UNAUTHORIZED'))
        rethrow;
      throw StateError('STORAGE_BLOCKED');
    } finally {
      if (!transferred && safeToRelease) _reserved = false;
    }
  }

  WorkspaceSnapshot get snapshot {
    _ensure();
    if (_authorityUnavailable) throw StateError('STORAGE_BLOCKED');
    return _snapshot;
  }

  /// Same key proof without exporting a key/MAC or granting a wire capability.
  void assertAutomationCustody(KeyCustody custody, ReceiptKeyMaterial key) {
    _ensure();
    try {
      if (key.workspaceId != _state.workspaceId ||
          key.receiptKeyId != _state.receiptKeyId ||
          key.ownerSid != _state.ownerSid ||
          custody.ownerSid != _state.ownerSid) {
        throw StateError('STORAGE_BLOCKED');
      }
      final input = <String, Object?>{
        'purpose': 'profile-service-key-binding-v1',
      };
      final expected = base64.decode(
        _custody.receiptDigestSync(_receiptKey, input),
      );
      final actual = base64.decode(custody.receiptDigestSync(key, input));
      var difference = expected.length ^ actual.length;
      for (var n = 0; n < expected.length; n++) {
        difference |= expected[n] ^ (n < actual.length ? actual[n] : 0);
      }
      if (difference != 0) throw StateError('STORAGE_BLOCKED');
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  /// Explicit native schema3 entry; owner/session/gate admission is separate.
  Future<Map<String, Object?>> mutateOwnerGrant(
    OwnerGrantCommand command, {
    required DateTime Function() clock,
  }) => _mutateOwnerGrant(command, clock);

  Future<Map<String, Object?>> _mutateOwnerGrant(
    OwnerGrantCommand command,
    DateTime Function() clock,
  ) {
    try {
      if (_closing) throw StateError('NOT_READY');
      _ensure();
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
      if (!{
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
      _blocked = true;
      return Future.error(StateError('STORAGE_BLOCKED'));
    }
  }

  WorkspaceState get state {
    _ensure();
    return _state;
  }

  void _ensure() {
    if (_blocked || _closed || _closing || !_lease.isHeld)
      throw StateError('STORAGE_BLOCKED');
    try {
      if (_files.root != _localAppData ||
          _files.ownerIdentity != _state.ownerSid ||
          _lease.ownerIdentity != _state.ownerSid ||
          _lease.workspaceSlot != 'default')
        throw StateError('STORAGE_BLOCKED');
      _files.requirePath(_localAppData);
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<void> _runtimeLive() async {
    _grantLive();
    try {
      await _runtime.revalidate();
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
    _grantLive();
  }

  Future<T> _writeStorage<T>(
    Future<T> Function(WorkspaceWriteTransaction transaction) action,
  ) async {
    await _runtimeLive();
    final value = await _storage.writeTransaction(action);
    await _runtimeLive();
    return value;
  }

  Future<void> close() => _closeOperation ??= _close();

  Future<void> _close() async {
    _closing = true;
    _settleAuthorityPublication();
    await _tail;
    try {
      if (!await _storage.close()) throw StateError('STORAGE_BLOCKED');
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
