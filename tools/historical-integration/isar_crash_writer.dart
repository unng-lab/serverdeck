import 'dart:ffi';
import 'dart:io';

import 'package:isar_community/isar.dart';
import 'package:serverdeck/storage/records.dart';

Future<void> main(List<String> args) async {
  await Isar.initializeIsarCore(
    libraries: {Abi.windowsX64: args[1]},
    download: false,
  );
  final db = await Isar.open(
    [AppSettingsSchema],
    name: 'serverdeck',
    directory: args[0],
    relaxedDurability: false,
    inspector: false,
  );
  db.writeTxnSync(() {
    final settings = db.appSettings.getSync(1)!..theme = 'light';
    db.appSettings.putSync(settings);
    if (args[2] == 'uncommitted') {
      stdout.writeln('DURING');
      sleep(const Duration(hours: 1));
    }
  });
  stdout.writeln('COMMITTED');
  sleep(const Duration(hours: 1));
}
