import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import 'private_marker_scan.dart';

void check(bool condition) {
  if (!condition) throw StateError('PRIVATE_FILE_SCAN_FAILED');
}

Future<Map<String, Object?>> scanUiPrivateFilesInIsolate(
  String root,
  List<String> accessMarkers,
  String pem,
) => Isolate.run(() => scanUiPrivateFiles(root, accessMarkers, pem));

/// Imported only by the compiled integration target, never by production UI.
Future<Map<String, Object?>> scanUiPrivateFiles(
  String root,
  List<String> accessMarkers,
  String pem,
) async {
  final fixture = p.dirname(p.dirname(Platform.resolvedExecutable));
  check(RegExp(r'^foundation-ui-[a-f0-9]{32}$').hasMatch(p.basename(fixture)));
  check(p.equals(p.normalize(p.absolute(root)), p.join(fixture, 'profile')));
  requireSafePath(root, root);
  final product = p.join(root, 'ServerDeckNext');
  final active = p.join(product, 'v1', 'workspaces', 'default');
  final sid = currentUserSid();
  check(
    !File(p.join(product, 'v1', 'runtime', 'default.discovery')).existsSync(),
  );
  requireSafePath(root, active);
  requireOwnerOnlyFileAcl(product, sid);
  requireOwnerOnlyFileAcl(active, sid);
  final scan = PrivateMarkerScan();
  List<int>? clear;
  try {
    for (final marker in accessMarkers) {
      scan.addSecretText(marker);
    }
    scan.addSecretText(pem);
    final body = pem
        .split(RegExp(r'\r?\n'))
        .where((line) => line.isNotEmpty && !line.startsWith('-----'))
        .join();
    final keyBytes = base64.decode(body);
    try {
      check(keyBytes.length >= 32);
      scan.addSecretText(body);
      scan.addSecretBytes(keyBytes);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
    clear = await DpapiProtection().unprotect(
      await readProtectedFile(
        root,
        p.join(active, 'receipt-key.dpapi'),
        sid,
        maxBytes: 16384,
      ),
      utf8.encode('ServerDeckNext\nv1\ndefault\n$sid\nreceipt'),
    );
    final wrapper = StrictCodec().decode(clear, maxBytes: 8192);
    check(
      wrapper['format'] == 1 &&
          wrapper['product'] == 'serverdeck-next' &&
          wrapper['ownerSid'] == sid,
    );
    final manifest = StrictCodec().decode(
      await readProtectedFile(
        root,
        p.join(active, 'workspace.manifest.json'),
        sid,
        maxBytes: 4096,
      ),
      maxBytes: 4096,
    );
    check(
      manifest['schema'] == 1 &&
          manifest['product'] == 'serverdeck-next' &&
          manifest['ownerSid'] == sid &&
          manifest['workspaceId'] == wrapper['workspaceId'] &&
          manifest['receiptKeyId'] == wrapper['receiptKeyId'],
    );
    final receiptBytes = base64.decode(wrapper['receiptKey'] as String);
    try {
      check(receiptBytes.length == 32);
      scan.addSecretBytes(receiptBytes);
    } finally {
      receiptBytes.fillRange(0, receiptBytes.length, 0);
    }
    clear.fillRange(0, clear.length, 0);
    clear = null;
    var files = 0, bytes = 0;
    final names = <String>{};
    for (final entry in Directory(
      product,
    ).listSync(recursive: true, followLinks: false)) {
      requireSafePath(root, entry.path);
      requireOwnerOnlyFileAcl(entry.path, sid);
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      check(
        type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory,
      );
      if (type == FileSystemEntityType.file) {
        bytes += await scan.assertCleanFile(File(entry.path));
        files++;
        if (p.equals(p.dirname(entry.path), active))
          names.add(p.basename(entry.path));
      }
    }
    check(
      names.containsAll({
        'workspace.isar',
        'workspace.isar-lck',
        'receipt-key.dpapi',
        'workspace.manifest.json',
      }),
    );
    check(files >= 4 && bytes > 0);
    return {
      'privateFilesScanned': files,
      'privateBytesScanned': bytes,
      'receiptKeyScan': true,
      'scanAfterDiscoveryRemoval': true,
    };
  } finally {
    clear?.fillRange(0, clear.length, 0);
    scan.close();
  }
}
