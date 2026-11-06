import 'dart:io';
import 'dart:typed_data';

import 'package:isar_community/isar.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/storage/workspace_store.dart';

/// Models only the store's calls, never Isar durability or native behavior.
class FakeStoreBackend implements StoreBackend {
  final Map<String, FakeDatabase> databases = {};
  final List<String> initialized = [];
  final List<String> openedPaths = [];
  Future<void> Function(String)? beforeOpen;

  @override
  Future<void> initialize(String libraryPath) async {
    initialized.add(libraryPath);
  }

  @override
  Future<Isar> open(String path) async {
    openedPaths.add(path);
    await beforeOpen?.call(path);
    final id = path.split('/').last.replaceFirst('staging-', '');
    await File('$path/serverdeck.isar').writeAsString('synthetic fixture');
    return databases.putIfAbsent(id, FakeDatabase.new);
  }
}

Future<Uint8List> fakeProtectReceiptKey(Uint8List bytes) async => Uint8List(64);

SecurityState copySecurity(SecurityState value) => SecurityState()
  ..id = value.id
  ..protectedReceiptHmacKey = [...value.protectedReceiptHmacKey]
  ..authorizationEpoch = value.authorizationEpoch
  ..minimumClockUtc = value.minimumClockUtc
  ..lastAuthorizationUtc = value.lastAuthorizationUtc
  ..lastClockRollbackAt = value.lastClockRollbackAt;

AppSettings copySettings(AppSettings value) => AppSettings()
  ..id = value.id
  ..logicalFormat = value.logicalFormat
  ..settingsRevision = value.settingsRevision
  ..dataRevision = value.dataRevision
  ..profilesListRevision = value.profilesListRevision
  ..theme = value.theme
  ..terminalConfiguration = value.terminalConfiguration
  ..mcpEnabled = value.mcpEnabled
  ..createdAt = value.createdAt
  ..lastSuccessfulOpenAt = value.lastSuccessfulOpenAt;

class FakeDatabase implements Isar {
  final settings = FakeSettings();
  final security = FakeSecurity();
  int syncTransactions = 0;
  int readTransactions = 0;
  bool _inSyncTransaction = false;
  int closes = 0;
  int failingCloses = 0;
  bool failNextTransaction = false;

  @override
  IsarCollection<T> collection<T>() {
    if (T == AppSettings) return settings as IsarCollection<T>;
    if (T == SecurityState) return security as IsarCollection<T>;
    throw StateError('Unexpected collection: $T');
  }

  @override
  Future<T> writeTxn<T>(
    Future<T> Function() callback, {
    bool silent = false,
  }) async {
    final previous = settings.value == null
        ? null
        : copySettings(settings.value!);
    final previousSecurity = security.value == null
        ? null
        : copySecurity(security.value!);
    try {
      final result = await callback();
      if (failNextTransaction) {
        failNextTransaction = false;
        throw StateError('synthetic transaction failure');
      }
      return result;
    } catch (_) {
      settings.value = previous;
      security.value = previousSecurity;
      rethrow;
    }
  }

  @override
  T writeTxnSync<T>(T Function() callback, {bool silent = false}) {
    if (_inSyncTransaction) throw StateError('Nested transaction');
    _inSyncTransaction = true;
    syncTransactions++;
    final previous = settings.value == null
        ? null
        : copySettings(settings.value!);
    final previousSecurity = security.value == null
        ? null
        : copySecurity(security.value!);
    try {
      final result = callback();
      if (failNextTransaction) {
        failNextTransaction = false;
        throw StateError('synthetic transaction failure');
      }
      return result;
    } catch (_) {
      settings.value = previous;
      security.value = previousSecurity;
      rethrow;
    } finally {
      _inSyncTransaction = false;
    }
  }

  @override
  T txnSync<T>(T Function() callback) {
    if (_inSyncTransaction) throw StateError('Nested transaction');
    readTransactions++;
    _inSyncTransaction = true;
    try {
      return callback();
    } finally {
      _inSyncTransaction = false;
    }
  }

  @override
  Future<bool> close({bool deleteFromDisk = false}) async {
    closes++;
    if (failingCloses > 0) {
      failingCloses--;
      return false;
    }
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected Isar call: ${invocation.memberName}');
}

class FakeSecurity implements IsarCollection<SecurityState> {
  SecurityState? value;
  @override
  SecurityState? getSync(Id id) =>
      value?.id == id ? copySecurity(value!) : null;
  @override
  Future<SecurityState?> get(Id id) async => getSync(id);
  @override
  Id putSync(SecurityState object, {bool saveLinks = true}) {
    value = copySecurity(object);
    return object.id;
  }

  @override
  Future<Id> put(SecurityState object) async => putSync(object);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Unexpected security collection call: ${invocation.memberName}',
  );
}

class FakeSettings implements IsarCollection<AppSettings> {
  AppSettings? value;

  @override
  AppSettings? getSync(Id id) => value?.id == id ? copySettings(value!) : null;

  @override
  Future<AppSettings?> get(Id id) async => getSync(id);

  @override
  Id putSync(AppSettings object, {bool saveLinks = true}) {
    value = copySettings(object);
    return object.id;
  }

  @override
  Future<Id> put(AppSettings object) async => putSync(object);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected collection call: ${invocation.memberName}');
}
