import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/ports.dart';

const owner = 'S-1-5-21-1-2-3-1001';

/// In-memory path/data semantics only; no real ACL/filesystem or encryption.
class Files implements ProtectedFiles {
  Files() {
    dirs.add(root);
    var path = root;
    for (final segment in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      path = p.join(path, segment);
      dirs.add(path);
    }
  }
  @override
  final String root = p.absolute('unit-memory-root');
  @override
  String get ownerIdentity => owner;
  final dirs = <String>{}, denied = <String>{};
  final data = <String, List<int>>{};
  int writes = 0;
  bool noSpace = false, failRename = false;
  @override
  void requirePath(String path) {
    if ((!p.equals(path, root) && !p.isWithin(root, path)) ||
        denied.contains(path))
      throw StateError('private-path-diagnostic');
  }

  @override
  void requireOwnerOnly(String path) {
    requirePath(path);
    if (!dirs.contains(path) && !data.containsKey(path))
      throw StateError('private-owner-diagnostic');
  }

  @override
  ProtectedPathKind kind(String path) {
    requirePath(path);
    return dirs.contains(path)
        ? ProtectedPathKind.directory
        : data.containsKey(path)
        ? ProtectedPathKind.file
        : ProtectedPathKind.absent;
  }

  @override
  int fileSize(String path) {
    requireOwnerOnly(path);
    return data[path]!.length;
  }

  @override
  Stream<String> children(String directory) async* {
    requireOwnerOnly(directory);
    for (final path in [...dirs, ...data.keys]) {
      if (p.dirname(path) == directory) yield path;
    }
  }

  @override
  void createDirectory(String path) {
    requirePath(path);
    if (!dirs.contains(p.dirname(path))) throw StateError('STORAGE_BLOCKED');
    dirs.add(path);
  }

  @override
  Future<List<int>> readFile(String path, {required int maxBytes}) async {
    requireOwnerOnly(path);
    final value = data[path];
    if (value == null || value.length > maxBytes)
      throw StateError('STORAGE_BLOCKED');
    return List.of(value);
  }

  @override
  Future<void> writeNewFile(String path, List<int> bytes) async {
    requirePath(path);
    if (data.containsKey(path) || !dirs.contains(p.dirname(path)))
      throw StateError('STORAGE_BLOCKED');
    data[path] = List.of(bytes);
    writes++;
  }

  @override
  Future<void> replaceFile(String path, List<int> bytes) async {
    requirePath(path);
    data[path] = List.of(bytes);
    writes++;
  }

  @override
  Future<void> createEmptyFile(String path) => writeNewFile(path, []);
  @override
  Future<void> promotePath(
    String source,
    String destination, {
    bool replace = false,
  }) async {
    requirePath(source);
    requirePath(destination);
    if (failRename ||
        !data.containsKey(source) ||
        !replace && data.containsKey(destination))
      throw StateError('private-rename-diagnostic');
    data[destination] = data.remove(source)!;
  }

  @override
  Future<void> requireFreeBytes(String path, int minimumBytes) async {
    requireOwnerOnly(path);
    if (noSpace) throw StateError('RESOURCE_LIMIT');
  }
}

final class Protection implements UserProtection {
  final records = <int, ({List<int> clear, String entropy})>{};
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> entropy) async {
    final id = records.length + 1;
    records[id] = (clear: List.of(cleartext), entropy: entropy.toString());
    return [id];
  }

  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) async {
    final row = ciphertext.length == 1 ? records[ciphertext.single] : null;
    if (row == null || row.entropy != entropy.toString())
      throw StateError('PROTECTION_UNAVAILABLE');
    return List.of(row.clear);
  }

  void dispose() {
    for (final row in records.values) {
      row.clear.fillRange(0, row.clear.length, 0);
    }
    records.clear();
  }
}
