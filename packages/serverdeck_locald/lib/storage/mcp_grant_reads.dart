part of 'state_store.dart';

/// Owns one private key handle. Only the trusted server composition sees it.
final class McpGrantKey {
  McpGrantKey._(this.grant, this.key);
  final ClientGrantRecord grant;
  final McpClientKey key;
  void close() => key.close();
}

extension _McpGrantReads on StateStore {
  void _mcpReady() {
    _ensure();
    // Publication is a temporary gate, not evidence of corrupt custody.
    if (_authorityUnavailable || _operational == null)
      throw StateError('STORAGE_BLOCKED');
    try {
      _grantLive();
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  ClientGrantRecord _currentMcpGrant(String id, {required DateTime at}) {
    _mcpReady();
    final grant = _operational!.automation.grants[id];
    if (grant == null || !grant.isCurrentAt(at))
      throw StateError('UNAUTHORIZED');
    return grant;
  }

  Future<McpGrantKey> _openMcpGrantKey(
    String id, {
    required DateTime Function() clock,
  }) async {
    final before = _currentMcpGrant(id, at: clock());
    late final McpClientKey key;
    try {
      key = await _grantFiles().openReferenced(_grantBinding(before));
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
    var transferred = false;
    try {
      final after = _currentMcpGrant(id, at: clock());
      if (after.revision != before.revision ||
          after.secretRef != before.secretRef ||
          after.workspaceId != before.workspaceId)
        throw StateError('UNAUTHORIZED');
      transferred = true;
      return McpGrantKey._(after, key);
    } finally {
      if (!transferred) key.close();
    }
  }
}
