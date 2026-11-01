import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate' show RemoteError;

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:serverdeck_engine/platform/managed_vault.dart';
import 'package:serverdeck_protocol/discovery.dart';

import 'embedded_build_bundle.dart';
import 'dpapi.dart';
import 'mutex.dart';
import 'paths.dart';
import 'security.dart';
import 'publication_gate.dart';

/// Bundle4/current-app binding for one Host lifetime. The composition root
/// retains the borrowed self process identity through Host close. Every gate
/// additionally owns its own current-process handle until its physical drain.
final class WindowsVerifiedRuntime implements VerifiedRuntime {
  WindowsVerifiedRuntime({
    required EmbeddedBuildBundle bundle,
    required VerifiedApplicationPeer self,
    void Function()? onUnconfirmedClose,
  }) : _bundle = bundle,
       _self = self,
       _onUnconfirmedClose = onUnconfirmedClose,
       ownerIdentity = self.ownerSid,
       appRoot = bundle.appRoot,
       buildId = bundle.buildId {
    _self.requireCurrentProcess(_bundle);
    if (_bundle.manifest.testOnly) throw StateError('UNAUTHORIZED');
  }
  final EmbeddedBuildBundle _bundle;
  final VerifiedApplicationPeer _self;
  final void Function()? _onUnconfirmedClose;
  @override
  final String ownerIdentity, appRoot, buildId;
  WindowsWorkspaceLease? _lease;
  Future<WindowsPublicationGate>? _gate;
  String? _generation;
  bool _failed = false;

  void _check(WorkspaceLease lease) {
    try {
      if (_failed ||
          lease is! WindowsWorkspaceLease ||
          !lease.isHeld ||
          lease.ownerIdentity != ownerIdentity ||
          lease.workspaceSlot != 'default' ||
          (_lease != null && !identical(_lease, lease)) ||
          _bundle.appRoot != appRoot ||
          _bundle.buildId != buildId ||
          currentUserSid() != ownerIdentity)
        throw StateError('UNAUTHORIZED');
      _self.requireCurrentProcess(_bundle);
      if (!lease.isHeld) throw StateError('UNAUTHORIZED');
      _lease ??= lease;
    } catch (_) {
      _failed = true;
      throw StateError('UNAUTHORIZED');
    }
  }

  @override
  Future<void> revalidate(WorkspaceLease lease) async => _check(lease);

  @override
  Future<PublicationGate> createPublicationGate(
    String generation,
    WorkspaceLease lease,
  ) {
    try {
      _check(lease);
      if (_generation != null && _generation != generation) {
        throw StateError('UNAUTHORIZED');
      }
      if (_gate != null) return _gate!;
      _generation = generation;
      final result = Completer<WindowsPublicationGate>();
      _gate = result.future;
      VerifiedApplicationPeer? proof;
      Future<WindowsPublicationGate>.sync(
        () => WindowsPublicationGate.open(
          ownerIdentity: ownerIdentity,
          appRoot: appRoot,
          generation: generation,
          verifyCurrentProcess: (identity) {
            _check(lease);
            proof ??= _bundle.verifyPeer(identity, ownerIdentity);
            proof!.requireCurrentProcess(_bundle);
            _check(lease);
          },
        ),
      ).then<void>(
        result.complete,
        onError: (Object error, StackTrace __) {
          _failed = true;
          if (error is StateError &&
              error.message == 'PHYSICAL_CLOSE_UNCONFIRMED') {
            try {
              _onUnconfirmedClose?.call();
            } catch (_) {
              /* Safe failure below. */
            }
          }
          result.completeError(StateError('SERVICE_UNAVAILABLE'));
        },
      );
      return result.future;
    } catch (_) {
      return Future.error(StateError('UNAUTHORIZED'));
    }
  }
}

void _owner(String ownerIdentity) {
  if (currentUserSid() != ownerIdentity) throw StateError('STORAGE_BLOCKED');
}

SecureVault createWindowsVault({required String ownerIdentity}) {
  _owner(ownerIdentity);
  return ManagedVault(
    DpapiProtection(),
    requireOwner: () => _owner(ownerIdentity),
  );
}

/// Owns one real acquire attempt; Host must close even an unheld/busy attempt.
/// Only Host knows when the store has physically closed and may release it.
final class WindowsWorkspaceLease implements WorkspaceLease {
  WindowsWorkspaceLease._(this.ownerIdentity, this._lease);
  final MutexLease _lease;
  @override
  final String ownerIdentity;
  @override
  String get workspaceSlot => 'default';
  @override
  String get name => _lease.name;
  bool get abandoned => _lease.abandoned;
  @override
  bool get acquired => _lease.acquired;
  @override
  bool get isHeld {
    try {
      _owner(ownerIdentity);
      return _lease.isHeld;
    } catch (_) {
      return false;
    }
  }

  Future<void>? _closing;
  static Future<WindowsWorkspaceLease> acquire({
    required String ownerIdentity,
  }) async {
    _owner(ownerIdentity);
    final namespace = await DiscoveryNamespace.forOwner(ownerIdentity);
    _owner(ownerIdentity);
    return WindowsWorkspaceLease._(
      ownerIdentity,
      await MutexLease.acquire(namespace.mutexName, ownerIdentity),
    );
  }

  @override
  Future<void> close() => _closing ??= _lease.close();
}

/// Native ACL/reparse/atomic I/O adapter. The bound root is the current user's
/// LocalAppData ancestor; domain paths remain inside its protected product tree.
final class WindowsProtectedFiles implements ProtectedFiles {
  factory WindowsProtectedFiles({
    required String root,
    required String ownerIdentity,
    void Function()? onUnconfirmedClose,
  }) {
    try {
      _owner(ownerIdentity);
      if (!p.isAbsolute(root)) throw StateError('STORAGE_BLOCKED');
      final canonical = p.normalize(root);
      requireSafePath(canonical, canonical);
      return WindowsProtectedFiles._(
        canonical,
        ownerIdentity,
        onUnconfirmedClose,
      );
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }
  WindowsProtectedFiles._(
    this.root,
    this.ownerIdentity,
    this._onUnconfirmedClose,
  );
  final void Function()? _onUnconfirmedClose;
  @override
  final String root, ownerIdentity;
  @override
  void requirePath(String path) {
    _path(path);
  }

  String _path(String path) {
    try {
      _owner(ownerIdentity);
      final resolved = validateLocalPath(root, path);
      requireSafePath(root, resolved);
      return resolved;
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  void requireOwnerOnly(String path) {
    final resolved = _path(path);
    try {
      requireOwnerOnlyFileAcl(resolved, ownerIdentity);
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  ProtectedPathKind kind(String path) {
    try {
      return switch (FileSystemEntity.typeSync(
        _path(path),
        followLinks: false,
      )) {
        FileSystemEntityType.notFound => ProtectedPathKind.absent,
        FileSystemEntityType.file => ProtectedPathKind.file,
        FileSystemEntityType.directory => ProtectedPathKind.directory,
        _ => throw StateError('STORAGE_BLOCKED'),
      };
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  int fileSize(String path) {
    requireOwnerOnly(path);
    if (kind(path) != ProtectedPathKind.file)
      throw StateError('STORAGE_BLOCKED');
    try {
      final size = File(_path(path)).lengthSync();
      requireOwnerOnly(path);
      return size;
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  Stream<String> children(String directory) async* {
    try {
      requireOwnerOnly(directory);
      if (kind(directory) != ProtectedPathKind.directory)
        throw StateError('STORAGE_BLOCKED');
      await for (final entry in Directory(
        _path(directory),
      ).list(followLinks: false)) {
        requireOwnerOnly(directory);
        requireOwnerOnly(entry.path);
        kind(entry.path); // Reject links/other entity types before yielding.
        yield entry.path;
      }
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<T> _io<T>(Future<T> Function() work) async {
    try {
      _owner(ownerIdentity);
      final result = await work();
      try {
        _owner(ownerIdentity);
      } catch (_) {
        if (result is List<int>) result.fillRange(0, result.length, 0);
        rethrow;
      }
      return result;
    } catch (error) {
      if ((error is FileSystemException &&
              error.message == 'PHYSICAL_CLOSE_UNCONFIRMED') ||
          error is RemoteError) {
        // A logical STORAGE_BLOCKED result cannot erase native cleanup failure.
        // Trusted composition retains it through final runtime/metadata drain.
        try {
          _onUnconfirmedClose?.call();
        } catch (_) {
          /* Never expose callback text. */
        }
      }
      if (error is FileSystemException && error.message == 'RESOURCE_LIMIT')
        throw StateError('RESOURCE_LIMIT');
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  void createDirectory(String path) {
    try {
      _owner(ownerIdentity);
      createProtectedDirectory(root, _path(path), ownerIdentity);
    } catch (_) {
      throw StateError('STORAGE_BLOCKED');
    }
  }

  @override
  Future<List<int>> readFile(String path, {required int maxBytes}) => _io(
    () =>
        readProtectedFile(root, _path(path), ownerIdentity, maxBytes: maxBytes),
  );
  @override
  Future<void> writeNewFile(String path, List<int> bytes) =>
      _io(() => writeNewProtectedFile(root, _path(path), ownerIdentity, bytes));
  @override
  Future<void> replaceFile(String path, List<int> bytes) =>
      _io(() => replaceProtectedFile(root, _path(path), ownerIdentity, bytes));
  @override
  Future<void> createEmptyFile(String path) =>
      _io(() => createProtectedEmptyFile(root, _path(path), ownerIdentity));
  @override
  Future<void> promotePath(
    String source,
    String destination, {
    bool replace = false,
  }) => _io(
    () => promoteProtectedPath(
      root,
      _path(source),
      _path(destination),
      ownerIdentity,
      replace: replace,
    ),
  );
  @override
  Future<void> requireFreeBytes(String path, int minimumBytes) => _io(
    () => requireProtectedDiskSpace(
      root,
      _path(path),
      ownerIdentity,
      minimumBytes: minimumBytes,
    ),
  );
}

String? _coreIdentity;
Future<void>? _coreLoading;

/// Only the composition root initializes the native core, before any store
/// access. DLL lifetime is the process lifetime; this adapter never opens a DB.
final class WindowsNativeStoreRuntime implements NativeStoreRuntime {
  WindowsNativeStoreRuntime({
    required EmbeddedBuildBundle bundle,
    required VerifiedApplicationPeer self,
  }) : _bundle = bundle,
       _self = self;
  final EmbeddedBuildBundle _bundle;
  final VerifiedApplicationPeer _self;
  Future<void>? _initializing;
  bool _initialized = false, _failed = false;

  void _check() {
    if (_failed) throw StateError('PREREQUISITE_UNAVAILABLE');
    if (!Platform.isWindows ||
        Abi.current() != Abi.windowsX64 ||
        Isar.version != '3.3.2')
      throw StateError('PREREQUISITE_UNAVAILABLE');
    if (_bundle.manifest.testOnly) throw StateError('UNAUTHORIZED');
    _self.requireCurrentProcess(_bundle);
  }

  static StateError _safe(Object error) => StateError(
    error is StateError &&
            const {
              'INCOMPATIBLE',
              'UNAUTHORIZED',
              'PREREQUISITE_UNAVAILABLE',
            }.contains(error.message)
        ? error.message
        : 'PREREQUISITE_UNAVAILABLE',
  );

  @override
  Future<void> initialize() {
    if (_failed)
      return Future<void>.error(StateError('PREREQUISITE_UNAVAILABLE'));
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      _check();
      final identity =
          'embedded4\nschema3\n${_bundle.appRoot}\n${_bundle.manifest.buildId}\n${_bundle.manifest.sha256['libisar.dll']}';
      if (_coreIdentity != null && _coreIdentity != identity)
        throw StateError('INCOMPATIBLE');
      if (_coreLoading == null) {
        _coreIdentity = identity;
        // Keep failures sticky too. A second caller cannot load a replacement.
        _coreLoading = Future<void>.sync(
          () => Isar.initializeIsarCore(
            libraries: {Abi.windowsX64: p.join(_bundle.appRoot, 'libisar.dll')},
            download: false,
          ),
        );
      }
      await _coreLoading;
      _check();
      _initialized = true;
    } catch (error) {
      _failed = true;
      throw _safe(error);
    }
  }

  @override
  Future<void> revalidate() async {
    try {
      if (!_initialized) throw StateError('PREREQUISITE_UNAVAILABLE');
      _check();
    } catch (error) {
      _failed = true;
      throw _safe(error);
    }
  }
}
