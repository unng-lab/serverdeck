import 'dart:convert';
import 'dart:io';

import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import 'private_marker_scan.dart';
import 'state_store_child.dart' show check;

const crashPassword = 'synthetic-crash-secret';
const crashPassphrase = 'synthetic-api-crash-passphrase-226';
final crashKeyBytes = List<int>.generate(32, (index) => 101 + index);
final crashKey =
    '-----BEGIN PRIVATE KEY-----\n${base64.encode(crashKeyBytes)}\n-----END PRIVATE KEY-----\n';

/// Acceptance target only; observes owned cleartext before production DPAPI.
class ApiCrashMarkers {
  ApiCrashMarkers(this.root, this.sid) {
    scan.addSecretText(crashPassword);
    scan.addSecretText(crashPassphrase);
    scan.addSecretText(crashKey);
    scan.addSecretBytes(crashKeyBytes);
  }
  final String root, sid;
  final scan = PrivateMarkerScan();
  bool receiptObserved = false;

  void observe(List<int> clear) {
    final value = StrictCodec().decode(clear, maxBytes: 512 * 1024);
    if (value['receiptKey'] case final String encoded when !receiptObserved) {
      final bytes = base64.decode(encoded);
      try {
        check(bytes.length == 32);
        scan.addSecretBytes(bytes);
        receiptObserved = true;
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
  }

  Future<void> assertCleanTree() async {
    check(receiptObserved);
    requireSafePath(root, root);
    requireOwnerOnlyFileAcl(root, sid);
    var files = 0;
    for (final entry in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      requireSafePath(root, entry.path);
      requireOwnerOnlyFileAcl(entry.path, sid);
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      check(
        type == FileSystemEntityType.file ||
            type == FileSystemEntityType.directory,
      );
      if (type == FileSystemEntityType.file) {
        await scan.assertCleanFile(File(entry.path));
        files++;
      }
    }
    check(files >= 4);
  }

  void close() => scan.close();
}
