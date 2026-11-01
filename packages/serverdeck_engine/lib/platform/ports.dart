import 'dart:typed_data';

/// OS secret protection. The caller owns and clears transient input buffers.
/// Implementations must never fall back to plaintext or replace an unavailable
/// protection key. Keeping this contract outside native adapters lets domain
/// custody run without loading a platform library.
abstract interface class UserProtection {
  // Returned buffers must be mutable, exclusively owned by the caller.
  Future<List<int>> protect(List<int> cleartext, List<int> entropy);
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy);
}

enum VaultAccess { available, locked, unavailable }

abstract interface class SecureVault implements UserProtection {
  Future<VaultAccess> accessStatus();
  Future<void> dispose();
}

/// Actual platform ownership, never a boolean or a DTO received from a client.
/// Only the host may close it, after store/native work has physically closed.
abstract interface class WorkspaceLease {
  String get ownerIdentity;
  String get workspaceSlot;
  String get name;

  /// Immutable result of this actual acquisition attempt. False means another
  /// writer held the lease; provider failures must throw instead. A lease that
  /// was acquired and subsequently lost still reports true here.
  bool get acquired;
  bool get isHeld;
  Future<void> close();
}

enum ProtectedPathKind { absent, file, directory }

/// Bound to the current OS owner and verified private-data ancestor root.
/// Implementors enforce ACLs and reject links/reparses on each operation.
/// Children are streamed at one level, not recursively collected in memory.
abstract interface class ProtectedFiles {
  String get root;
  String get ownerIdentity;
  void requirePath(String path);
  void requireOwnerOnly(String path);
  ProtectedPathKind kind(String path);
  int fileSize(String path);
  Stream<String> children(String directory);
  void createDirectory(String path);
  Future<List<int>> readFile(String path, {required int maxBytes});
  Future<void> writeNewFile(String path, List<int> bytes);
  Future<void> replaceFile(String path, List<int> bytes);
  Future<void> createEmptyFile(String path);
  Future<void> promotePath(
    String source,
    String destination, {
    bool replace = false,
  });
  Future<void> requireFreeBytes(String path, int minimumBytes);
}

/// Loads and revalidates the pinned native library, without opening a database.
/// Database handles belong to the engine store, not to this platform adapter.
abstract interface class NativeStoreRuntime {
  Future<void> initialize();
  Future<void> revalidate();
}

/// Cross-process publication ordering. It does not itself grant tool rights.
/// Timed-out acquisition remains charged until [PublicationAcquisition.settled].
abstract interface class PublicationGate {
  String get generation;
  bool get isClosed;
  int get activeAcquisitions;
  int get activeLeases;
  PublicationAcquisition beginAcquire({
    Duration deadline = const Duration(seconds: 5),
  });
  Future<PublicationLease> acquire({
    Duration deadline = const Duration(seconds: 5),
  });
  Future<void> close();
}

abstract interface class PublicationAcquisition {
  Future<PublicationLease> get result;
  Future<void> get settled;
}

abstract interface class PublicationLease {
  Future<void> get done;
  Future<void> close();
}

/// Issued by the platform composition root, not deserialized from a request.
/// Revalidation must check retained app identity AND the genuine OS lease.
/// Completing these futures denotes physical completion of the platform work.
abstract interface class VerifiedRuntime {
  String get ownerIdentity;
  String get appRoot;
  String get buildId;
  Future<void> revalidate(WorkspaceLease lease);
  Future<PublicationGate> createPublicationGate(
    String generation,
    WorkspaceLease lease,
  );
}

/// Retained, platform-verified app-to-MCP endpoint issued by the host root.
/// There is deliberately no caller-selected role or owner admission method.
/// Proof observers receive actual physical work, including late completion.
/// I/O honors the supplied remaining deadline. Disconnect is a physical reuse
/// barrier: all prior reads/writes/proofs are cancelled or settled before it
/// completes. Logical timeout alone must not allow endpoint/handle reuse.
abstract interface class VerifiedMcpChannel {
  String get ownerIdentity;
  String get appRoot;
  String get buildId;
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  });
  Future<Uint8List> read({required int count, required Duration deadline});
  Future<void> write(List<int> bytes, {required Duration deadline});
  Future<void> drainOutput({required Duration deadline});
  Future<void> disconnect();
}

/// Verified same-executable MCP configuration, not permission to invoke tools.
abstract interface class VerifiedAppConfiguration {
  String get appRoot;
  String get buildId;
  Map<String, Object?> mcpConfiguration(String grantId);
}

abstract interface class EngineClock {
  Duration get elapsed;
  DateTime get utcNow;
}

final class SystemEngineClock implements EngineClock {
  final _watch = Stopwatch()..start();
  @override
  Duration get elapsed => _watch.elapsed;
  @override
  DateTime get utcNow => DateTime.now().toUtc();
}
