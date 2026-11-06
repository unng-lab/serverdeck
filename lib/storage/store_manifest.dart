import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// This identifies incompatible data semantics, not every additive Isar schema.
const currentStorageFormat = 2;

/// Compatible schema additions retain the current data format.
bool isCompatibleStorageFormat(Object? value) =>
    value is int && value == currentStorageFormat;

final _storeId = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

class StoreFailure implements Exception {
  const StoreFailure(this.code);
  final String code;
  @override
  String toString() => code;
}

class StoreManifest {
  const StoreManifest(this.storeId);
  final String storeId;
  int get formatVersion => currentStorageFormat;
  String get relativeDirectory => 'stores/$storeId';
  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'publicationVersion': 1,
        'formatVersion': formatVersion,
        'storeId': storeId,
        'relativeDirectory': relativeDirectory,
      }),
    ),
  );

  static StoreManifest decode(List<int> bytes) {
    try {
      final value = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final id = value['storeId'];
      if (value['publicationVersion'] is! int ||
          value['publicationVersion'] != 1 ||
          !isCompatibleStorageFormat(value['formatVersion']) ||
          id is! String ||
          !_storeId.hasMatch(id) ||
          value['relativeDirectory'] != 'stores/$id') {
        throw const StoreFailure('INCOMPATIBLE_STORE');
      }
      return StoreManifest(id);
    } catch (_) {
      throw const StoreFailure('INCOMPATIBLE_STORE');
    }
  }
}

String newStoreId() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Native startup has secured the root ACL. Refuse links before any DB open.
Future<void> rejectLinks(String path) async {
  final absolute = File(path).absolute.path;
  var current = Directory(absolute);
  while (true) {
    if (await FileSystemEntity.type(current.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw const StoreFailure('STORAGE_IO');
    }
    final parent = current.parent;
    if (parent.path == current.path) break;
    current = parent;
  }
}

// Native monitoring publishes this bounded run marker before database startup.
// It is not an unpublished database, and storage must leave its bytes intact.
Future<bool> _isMonitoringRunMarker(FileSystemEntity entry) async {
  if (entry is! File ||
      entry.uri.pathSegments.last != 'monitoring-run-v1.json') {
    return false;
  }
  await rejectLinks(entry.path);
  final handle = await entry.open();
  try {
    final bytes = await handle.read(129);
    if (bytes.length > 128) return false;
    for (final expected in const [
      '{"version":1,"state":"running"}',
      '{"version":1,"state":"clean"}',
    ]) {
      if (bytes.length != expected.length) continue;
      var index = 0;
      while (index < bytes.length &&
          bytes[index] == expected.codeUnitAt(index)) {
        index++;
      }
      if (index == bytes.length) return true;
    }
    return false;
  } finally {
    await handle.close();
  }
}

Future<StoreManifest?> preflightStore(Directory data) async {
  await rejectLinks(data.path);
  final current = File('${data.path}/CURRENT.json');
  await rejectLinks(current.path);
  if (await current.exists()) {
    if (await current.length() > 4096) {
      throw const StoreFailure('INCOMPATIBLE_STORE');
    }
    final manifest = StoreManifest.decode(await current.readAsBytes());
    final selected = Directory('${data.path}/${manifest.relativeDirectory}');
    await rejectLinks(selected.path);
    if (!await selected.exists() ||
        !await File('${selected.path}/serverdeck.isar').exists()) {
      throw const StoreFailure('MISSING_STORE');
    }
    await for (final entry in selected.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectLinks(entry.path);
    }
    return manifest;
  }
  if (await data.exists()) {
    // Never guess which orphan or staging directory contains the user's data.
    await for (final entry in data.list(followLinks: false)) {
      if (await _isMonitoringRunMarker(entry)) continue;
      if (entry is Directory &&
          entry.path == '${data.path}${Platform.pathSeparator}stores') {
        if (await entry.list(followLinks: false).isEmpty) continue;
      }
      throw const StoreFailure('UNPUBLISHED_STORE');
    }
  }
  return null;
}

/// Only the live owner that created this UUID may resume it. A new process
/// still uses preflightStore and rejects unpublished directories.
Future<void> validatePendingPublication(
  Directory data,
  StoreManifest pending,
) async {
  await rejectLinks(data.path);
  if (!await data.exists()) return;
  final stage = 'staging-${pending.storeId}';
  await for (final entry in data.list(followLinks: false)) {
    await rejectLinks(entry.path);
    if (await _isMonitoringRunMarker(entry)) continue;
    final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entry is! Directory || (name != 'stores' && name != stage)) {
      throw const StoreFailure('UNPUBLISHED_STORE');
    }
    if (name == 'stores') {
      await for (final candidate in entry.list(followLinks: false)) {
        await rejectLinks(candidate.path);
        final id = candidate.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (candidate is! Directory || id != pending.storeId) {
          throw const StoreFailure('UNPUBLISHED_STORE');
        }
      }
    }
    await for (final candidate in entry.list(
      recursive: true,
      followLinks: false,
    )) {
      await rejectLinks(candidate.path);
    }
  }
}
