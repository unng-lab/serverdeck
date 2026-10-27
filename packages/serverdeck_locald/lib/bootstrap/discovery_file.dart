import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/mutex.dart';
import 'package:serverdeck_windows/native_attributes.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import 'discovery.dart';

/// The owner drains all queued publications/removal before releasing its lease.
class DiscoveryFile {
  DiscoveryFile({
    required this.localAppData,
    required this.runtimeDirectory,
    required this.ownerSid,
    required this.custody,
  });
  final String localAppData, runtimeDirectory, ownerSid;
  final DiscoveryCustody custody;
  static final Map<String, Future<void>> _publications = {};
  Future<void> _tail = Future.value();
  String get path => p.join(runtimeDirectory, 'default.discovery');
  String get _queueKey => p.normalize(p.absolute(path)).toLowerCase();

  Future<DiscoveryDescriptor> read(String expectedBuildId) async {
    try {
      _validate();
      final bytes = await readProtectedFile(
        localAppData,
        path,
        ownerSid,
        maxBytes: 16384,
      );
      return await custody.unprotect(bytes, expectedBuildId);
    } catch (error) {
      if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  void _validate() {
    if (custody.ownerSid != ownerSid) throw StateError('STORAGE_BLOCKED');
    requireSafePath(localAppData, runtimeDirectory);
    requireOwnerOnlyFileAcl(runtimeDirectory, ownerSid);
  }

  Future<void> _owned(MutexLease lease) async {
    try {
      final namespace = await DiscoveryNamespace.forOwner(ownerSid);
      if (!lease.isHeld || lease.name != namespace.mutexName)
        throw StateError('STORAGE_BLOCKED');
      _validate();
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final key = _queueKey;
    final previous = _publications[key] ?? Future<void>.value();
    final result = previous.then((_) => operation());
    final completed = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    _publications[key] = completed;
    _tail = completed;
    completed.then((_) {
      if (identical(_publications[key], completed)) _publications.remove(key);
    });
    return result;
  }

  Future<void> publish(DiscoveryDescriptor descriptor, MutexLease lease) {
    // Capture before asynchronous queuing: caller may close its token copy.
    final snapshot = descriptor.workspaceId == null
        ? DiscoveryDescriptor.decode(
            descriptor.encode(),
            ownerSid: ownerSid,
            expectedBuildId: descriptor.buildId,
          )
        : Future.value(descriptor.withWorkspace(descriptor.workspaceId!));
    // Observe errors even if the serialized operation is delayed.
    snapshot.ignore();
    return _serialize(() async {
      DiscoveryDescriptor? owned;
      try {
        owned = await snapshot;
        await _owned(lease);
        requireSafePath(localAppData, path);
        if (queryLocalAttributes(path) != null) {
          final existing = await custody.inspectForOwner(
            await readProtectedFile(
              localAppData,
              path,
              ownerSid,
              maxBytes: 16384,
            ),
          );
          try {
            if (existing.generation == owned.generation) {
              final oldToken = existing.bootstrapToken,
                  newToken = owned.bootstrapToken;
              try {
                var tokenDifference = 0;
                for (var i = 0; i < 32; i++) {
                  tokenDifference |= oldToken[i] ^ newToken[i];
                }
                if (tokenDifference != 0 ||
                    existing.buildId != owned.buildId ||
                    existing.serverPid != owned.serverPid ||
                    (existing.workspaceId != null &&
                        existing.workspaceId != owned.workspaceId)) {
                  throw StateError('STORAGE_BLOCKED');
                }
              } finally {
                oldToken.fillRange(0, oldToken.length, 0);
                newToken.fillRange(0, newToken.length, 0);
              }
            }
          } finally {
            existing.close();
          }
        }
        final wrapped = await custody.protect(owned);
        await _owned(lease);
        await replaceProtectedFile(localAppData, path, ownerSid, wrapped);
        await _owned(lease);
      } catch (error) {
        if (error is StateError && error.message == 'INCOMPATIBLE') rethrow;
        throw StateError('STORAGE_BLOCKED');
      } finally {
        owned?.close();
      }
    });
  }

  Future<void> remove(
    String generation,
    String expectedBuildId,
    MutexLease lease,
  ) => _serialize(() async {
    await _owned(lease);
    // Missing/corrupt/foreign descriptors are not silently deleted.
    final descriptor = await read(expectedBuildId);
    try {
      if (descriptor.generation != generation)
        throw StateError('STORAGE_BLOCKED');
      await _owned(lease);
      requireSafePath(localAppData, path);
      requireOwnerOnlyFileAcl(path, ownerSid);
      await File(path).delete();
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    } finally {
      descriptor.close();
    }
  });
  Future<void> get drained => _publications[_queueKey] ?? _tail;
}
