import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/storage/records.dart';

void require(bool value) {
  if (!value) throw StateError('NATIVE_COMMIT_PROOF_FAILED');
}

Future<void> main(List<String> args) async {
  final root = p.normalize(p.absolute(args[0])), sync = args[1] == 'sync';
  require(
    p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), root) &&
        p.basename(root).startsWith('serverdeck-mcp-bundle-commit-'),
  );
  await Isar.initializeIsarCore(
    libraries: {Abi.windowsX64: p.join(root, 'libisar.dll')},
    download: false,
  );
  final native = await Isar.open(
    workspaceSchemas,
    directory: root,
    name: 'commit-probe',
    maxSizeMiB: 64,
    relaxedDurability: false,
    inspector: false,
  );
  const original =
      '{"revision":"1","theme":"system","reduceMotion":false,"selectedProfileId":null}';
  const alternate =
      '{"revision":"1","theme":"system","reduceMotion":true,"selectedProfileId":null}';
  await native.writeTxn(() async {
    await native.storedSettings.put(StoredSettings()..payload = original);
  });
  // Preserve callback-failure abort and its physical reply-port cleanup too.
  try {
    await native.writeTxn(() async {
      await native.storedSettings.put(StoredSettings()..payload = alternate);
      throw StateError('OWNED_CALLBACK_FAILURE');
    });
  } on StateError catch (error) {
    require(error.message == 'OWNED_CALLBACK_FAILURE');
  }
  require((await native.storedSettings.get(1))!.payload == original);
  final ready = Completer<void>(), release = Completer<void>();
  final reader = native.txn(() async {
    require(await native.storedSettings.get(1) != null);
    ready.complete();
    await release.future;
  });
  await ready.future;
  var failed = false;
  try {
    for (var n = 0; n < 20000; n++) {
      var reachedCommit = false;
      try {
        if (sync) {
          native.writeTxnSync(() {
            native.storedSettings.putSync(
              StoredSettings()..payload = alternate,
            );
            native.storedSettings.putSync(StoredSettings()..payload = original);
            reachedCommit = true;
          });
        } else {
          await native.writeTxn(() async {
            await native.storedSettings.put(
              StoredSettings()..payload = alternate,
            );
            await native.storedSettings.put(
              StoredSettings()..payload = original,
            );
            reachedCommit = true;
          });
        }
      } on IsarError catch (error) {
        require(reachedCommit && error.message == 'The database is full.');
        failed = true;
        break;
      }
    }
    require(
      failed && (await native.storedSettings.get(1))!.payload == original,
    );
  } finally {
    release.complete();
    await reader;
  }
  await native.writeTxn(() async {
    await native.storedSettings.put(StoredSettings()..payload = alternate);
  });
  require((await native.storedSettings.get(1))!.payload == alternate);
  require(await native.close());
  stdout.writeln('PASS:commit-capacity:${args[1]}');
}
