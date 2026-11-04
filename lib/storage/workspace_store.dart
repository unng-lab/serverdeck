import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';

import '../runtime/capability.dart';
import 'store_manifest.dart';
import 'records.dart';

typedef FlushMetadata = Future<void> Function(String path, Uint8List bytes);
typedef ProtectReceiptKey = Future<Uint8List> Function(Uint8List bytes);

/// Boundary for native Isar access; unit tests supply an in-memory backend.
abstract interface class StoreBackend {
  Future<void> initialize(String libraryPath);
  Future<Isar> open(String path);
}

class IsarStoreBackend implements StoreBackend {
  const IsarStoreBackend();

  @override
  Future<void> initialize(String libraryPath) => Isar.initializeIsarCore(
    libraries: {Abi.windowsX64: libraryPath},
    download: false,
  );

  @override
  Future<Isar> open(String path) => Isar.open(
    workspaceSchemas,
    name: 'serverdeck',
    directory: path,
    relaxedDurability: false,
    inspector: false,
  );
}

/// The composition root owns this instance. Widgets never receive the Isar handle.
class WorkspaceStore implements RuntimeStore {
  WorkspaceStore({
    required this.dataRoot,
    required this.libraryPath,
    required this.flushAtomic,
    this.backend = const IsarStoreBackend(),
    this.protectReceiptKey,
  });
  final String dataRoot, libraryPath;
  final FlushMetadata flushAtomic;
  final StoreBackend backend;
  final ProtectReceiptKey? protectReceiptKey;
  Isar? _isar;
  bool _admission = false;
  Future<void> _writes = Future.value();
  Future<void>? _opening;
  AppSettings? _settings;
  StoreManifest? _initialPublication;
  bool _initialInitialized = false, _initialPrepared = false;
  Isar? _pendingClose;
  bool _closing = false, _admissionStopped = false;
  bool _inSyncTransaction = false;
  bool get isOpen => _isar != null;
  String get theme => _settings?.theme ?? 'dark';

  @override
  Future<void> open() {
    if (_closing) return Future.error(const StoreFailure('SHUTTING_DOWN'));
    if (_isar != null) return Future.value();
    if (_opening == null) _admissionStopped = false;
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<Isar> _openAt(String path) => backend.open(path);

  Future<void> _open() async {
    await _finishPendingClose();
    final data = Directory('$dataRoot/data');
    StoreManifest? selected;
    if (_initialPublication != null &&
        !await File('${data.path}/CURRENT.json').exists()) {
      await validatePendingPublication(data, _initialPublication!);
    } else {
      selected = await preflightStore(data);
      if (_initialPublication != null &&
          (selected?.storeId != _initialPublication!.storeId ||
              selected?.formatVersion != _initialPublication!.formatVersion)) {
        throw const StoreFailure('INCOMPATIBLE_STORE');
      }
    }
    if (!File(libraryPath).isAbsolute || !await File(libraryPath).exists()) {
      throw const StoreFailure('NATIVE_LIBRARY_UNAVAILABLE');
    }
    await backend.initialize(libraryPath);
    Isar? opened;
    try {
      final manifest =
          selected ?? _initialPublication ?? StoreManifest(newStoreId());
      final path = '${data.path}/${manifest.relativeDirectory}';
      if (selected == null) {
        _initialPublication = manifest;
        if (!_initialInitialized) {
          final staging = Directory('${data.path}/staging-${manifest.storeId}');
          await staging.create(recursive: true);
          opened = await _openAt(staging.path);
          final settings = await opened.appSettings.get(1) ?? AppSettings();
          _validateSettings(settings);
          final security = await _newSecurityIfMissing(opened);
          await opened.writeTxn(() async {
            await opened!.appSettings.put(settings);
            if (security != null) await opened!.securityStates.put(security);
          });
          await _closeOpening(opened);
          opened = null;
          _initialInitialized = true;
        }
        if (!_initialPrepared) {
          await flushAtomic('data/flush/${manifest.storeId}', Uint8List(0));
          opened = await _openAt('${data.path}/staging-${manifest.storeId}');
          _validateSettings(await opened.appSettings.get(1));
          _validateSecurity(await opened.securityStates.get(1));
          await _closeOpening(opened);
          opened = null;
          _initialPrepared = true;
        }
        // Flush and publish is native: directory and CURRENT form one ordered
        // publication; a crash before CURRENT produces an explicit orphan error.
        await flushAtomic(
          'data/publish/${manifest.storeId}',
          manifest.encode(),
        );
      }
      opened = await _openAt(path);
      final settings = _validateSettings(await opened.appSettings.get(1));
      _validateSecurity(await opened.securityStates.get(1));
      settings.lastSuccessfulOpenAt = DateTime.now()
          .toUtc()
          .millisecondsSinceEpoch;
      await opened.writeTxn(() => opened!.appSettings.put(settings));
      _settings = settings;
      _isar = opened;
      _admission = !_admissionStopped && !_closing;
      _initialPublication = null;
      _initialInitialized = _initialPrepared = false;
    } catch (_) {
      if (opened != null && !identical(opened, _pendingClose)) {
        await _closeOpening(opened);
      }
      rethrow;
    }
  }

  AppSettings _validateSettings(AppSettings? value) {
    if (value == null ||
        value.logicalFormat != 3 ||
        value.settingsRevision < 1 ||
        value.dataRevision < 1 ||
        value.profilesListRevision < 1 ||
        !{'dark', 'light'}.contains(value.theme)) {
      throw const StoreFailure('INCOMPATIBLE_STORE');
    }
    return value;
  }

  void _validateSecurity(SecurityState? value) {
    if (value == null ||
        value.id != 1 ||
        value.authorizationEpoch < 1 ||
        value.protectedReceiptHmacKey.isEmpty ||
        value.protectedReceiptHmacKey.length > 2 * 1024 * 1024) {
      throw const StoreFailure('INCOMPATIBLE_STORE');
    }
  }

  Future<SecurityState?> _newSecurityIfMissing(Isar db) async {
    final existing = await db.securityStates.get(1);
    if (existing != null) {
      _validateSecurity(existing);
      return null;
    }
    final protect = protectReceiptKey;
    if (protect == null) throw const StoreFailure('PROTECTION_UNAVAILABLE');
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(32, (_) => random.nextInt(256)),
    );
    late Uint8List protected;
    try {
      protected = await protect(bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final value = SecurityState()
      ..protectedReceiptHmacKey = protected.toList()
      ..minimumClockUtc = now
      ..lastAuthorizationUtc = now;
    _validateSecurity(value);
    return value;
  }

  Future<void> _closeOpening(Isar db) async {
    _pendingClose = db;
    if (!await db.close()) throw const StoreFailure('STORAGE_CLOSE_FAILED');
    _pendingClose = null;
  }

  Future<void> _finishPendingClose() async {
    if (_pendingClose != null) await _closeOpening(_pendingClose!);
  }

  /// Consistent owner-only read. Reuse the current synchronous transaction when
  /// canonical authorization/version checks run inside a write boundary.
  T readSync<T>(T Function(Isar db) reader) {
    final db = _isar;
    if (db == null) throw const StoreFailure('STORAGE_UNAVAILABLE');
    if (_inSyncTransaction) return reader(db);
    return db.txnSync(() {
      _inSyncTransaction = true;
      try {
        return reader(db);
      } finally {
        _inSyncTransaction = false;
      }
    });
  }

  /// Admission is synchronous; accepted leases are included in finishWrites.
  /// The callback must contain only local, synchronous Isar operations.
  Future<T> write<T>(T Function(Isar db) transaction) {
    if (!_admission || _isar == null) {
      return Future.error(const StoreFailure('SHUTTING_DOWN'));
    }
    final result = Completer<T>();
    _writes = _writes.then((_) async {
      try {
        final db = _isar!;
        final value = db.writeTxnSync(() {
          _inSyncTransaction = true;
          try {
            return transaction(db);
          } finally {
            _inSyncTransaction = false;
          }
        });
        result.complete(value);
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  void stopAdmission() {
    _admissionStopped = true;
    _admission = false;
  }

  @override
  Future<void> finishWrites() => _writes;
  @override
  Future<void> close() async {
    _closing = true;
    stopAdmission();
    try {
      try {
        await _opening;
      } catch (_) {
        /* The UI retains the startup error. */
      }
      await finishWrites();
      await _finishPendingClose();
      if (_isar != null) {
        if (!await _isar!.close())
          throw const StoreFailure('STORAGE_CLOSE_FAILED');
        _isar = null;
        _settings = null;
      }
    } finally {
      _closing = false;
    }
  }
}
