import 'dart:convert';
import 'dart:io';

import 'client.dart';
import 'models.dart';

String defaultDataDirectory() {
  if (Platform.isMacOS) {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw const LocalApiException('DataDirectoryUnavailable');
    }
    final legacy = '$home/.local/share/ServerDeck/demo';
    return Directory(legacy).existsSync()
        ? legacy
        : '$home/Library/Application Support/ServerDeck/demo';
  }
  final base = Platform.isWindows
      ? Platform.environment['LOCALAPPDATA']
      : Platform.environment['XDG_DATA_HOME'] ??
            '${Platform.environment['HOME']}/.local/share';
  if (base == null || base.isEmpty) {
    throw const LocalApiException('DataDirectoryUnavailable');
  }
  // Demo profiles are kept apart from future enrolled production hosts.
  return '$base/ServerDeck/demo';
}

Future<LocalApiClient?> discoverLocald(String directory) async {
  LocalApiClient? client;
  try {
    final file = File('$directory/endpoint.json');
    if (!await file.exists() || await file.length() > 4096) {
      return null;
    }
    final endpoint = jsonDecode(await file.readAsString()) as JsonMap;
    final port = endpoint['port'];
    final proof = endpoint['proof'];
    if (endpoint['apiVersion'] != localApiVersion ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        proof is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(proof)) {
      return null;
    }
    client = LocalApiClient(
      port: port,
      proof: proof,
      timeout: const Duration(seconds: 1),
    );
    await client.health();
    client.close();
    return LocalApiClient(port: port, proof: proof);
  } catch (_) {
    client?.close();
    return null;
  }
}

Future<LocalApiClient> ensureLocald({String? directory}) async {
  final root = directory ?? defaultDataDirectory();
  final existing = await discoverLocald(root);
  if (existing != null) {
    return existing;
  }
  final bundled = File(
    '${File(Platform.resolvedExecutable).parent.path}/'
    'serverdeck_locald${Platform.isWindows ? '.exe' : ''}',
  );
  final configured = Platform.environment['SERVERDECK_LOCALD_EXECUTABLE'];
  final executable = configured ?? bundled.path;
  if (!await File(executable).exists()) {
    throw const LocalApiException('LocaldExecutableMissing');
  }
  await Process.start(executable, [
    '--data-dir',
    root,
  ], mode: ProcessStartMode.detached);
  final timer = Stopwatch()..start();
  while (timer.elapsed < const Duration(seconds: 15)) {
    final client = await discoverLocald(root);
    if (client != null) {
      return client;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw const LocalApiException('LocaldStartupFailed');
}
