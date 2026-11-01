import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../platform/ports.dart';
import 'executor_enrollments.dart';
import 'key_custody.dart';
import 'native_schema.dart';
import 'workspace_rows.dart';
import 'workspace_snapshot.dart';

/// Read-only gate for protected bytes captured under the caller's writer lease.
/// Returns detached validated metadata, never native-open or owner authority.
/// Does not initialize a library, open a DB, publish a pointer or repair a file.
Future<WorkspaceSnapshot> preflightWorkspace(
  Uint8List bytes, {
  required ProtectedFiles files,
  required WorkspaceLease lease,
  required ReceiptKeyMaterial key,
  required KeyCustody custody,
}) => preflightWorkspaceRows(
  () => NativeWorkspaceRows.fromSnapshot(
    bytes,
    directory: p.join(
      files.root,
      'ServerDeckNext',
      'v1',
      'workspaces',
      'default',
    ),
  ),
  files: files,
  lease: lease,
  key: key,
  custody: custody,
);

/// Common semantic/custody gate. Source creation occurs only after owner checks;
/// neither a row source nor this result grants writable-open authority.
Future<WorkspaceSnapshot> preflightWorkspaceRows(
  WorkspaceRowSource Function() source, {
  required ProtectedFiles files,
  required WorkspaceLease lease,
  required ReceiptKeyMaterial key,
  required KeyCustody custody,
}) async {
  final root = files.root;
  void owner() {
    if (files.root != root ||
        !lease.isHeld ||
        lease.workspaceSlot != 'default' ||
        lease.ownerIdentity != key.ownerSid ||
        files.ownerIdentity != key.ownerSid ||
        custody.ownerSid != key.ownerSid)
      throw StateError('STORAGE_BLOCKED');
    files.requirePath(root);
  }

  try {
    owner();
    final snapshot = await inspectWorkspaceSnapshot(
      source(),
      key,
      custody,
      localAppData: root,
      lease: lease,
      protectedFiles: files,
    );
    owner();
    await ExecutorEnrollmentStore(
      files: files,
      lease: lease,
      custody: custody,
      key: key,
      requireReady: owner,
      onStorageBlocked: () {},
    ).read();
    owner();
    return snapshot;
  } catch (error) {
    if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
    throw StateError('STORAGE_BLOCKED');
  }
}
