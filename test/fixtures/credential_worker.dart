import 'dart:convert';
import 'dart:io';

import 'package:serverdeck/data/credentials.dart';

Future<void> main(List<String> args) async {
  try {
    if (args.length != 3 ||
        !{'write', 'delete'}.contains(args[1]) ||
        !{'a', 'b'}.contains(args[2])) {
      throw const FormatException('Invalid worker command');
    }
    final store = OsCredentialStore();
    final credential = SshCredential.key(
      'synthetic-${args[2]}-key',
      passphrase: 'synthetic-${args[2]}-phrase',
    );
    stdout.writeln('ready');
    await stdout.flush();
    final command = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    if (command != 'apply') {
      throw const FormatException('Invalid worker command');
    }
    if (args[1] == 'write') {
      await store.write(args[0], credential);
    } else {
      await store.delete(args[0]);
    }
    stdout.writeln('done');
    await stdout.flush();
  } catch (_) {
    stderr.writeln('Credential fixture failed');
    exitCode = 1;
  }
}
