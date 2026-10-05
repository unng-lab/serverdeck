import 'dart:async';
import 'dart:io';

import 'package:serverdeck_locald/locald.dart';

Future<void> main(List<String> arguments) async {
  String? directory;
  String? library;
  for (var i = 0; i < arguments.length; i += 2) {
    if (i + 1 >= arguments.length) {
      throw const FormatException('Missing option value');
    }
    switch (arguments[i]) {
      case '--data-dir':
        directory = arguments[i + 1];
      case '--library':
        library = arguments[i + 1];
      default:
        throw const FormatException('Unknown option');
    }
  }
  if (directory == null) {
    throw const FormatException('--data-dir required');
  }
  final libraryPath =
      library ??
      '${File(Platform.resolvedExecutable).parent.path}/'
          '${Platform.isWindows
              ? 'libisar.dll'
              : Platform.isLinux
              ? 'libisar.so'
              : 'libisar.dylib'}';
  LocaldServer server;
  try {
    server = await LocaldServer.start(
      directory: directory,
      nativeLibraryPath: libraryPath,
    );
  } on LocalApiException catch (e) {
    // Safe code only: never print API session proof, profile data or credentials.
    stderr.writeln(e.code);
    exitCode = 1;
    return;
  }
  final stop = Completer<void>();
  final subscriptions = <StreamSubscription<ProcessSignal>>[];
  for (final signal in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    try {
      subscriptions.add(
        signal.watch().listen(
          (_) {
            if (!stop.isCompleted) {
              stop.complete();
            }
          },
          onError: (Object _) {
            // Windows may report unsupported signals asynchronously.
          },
        ),
      );
    } catch (_) {
      /* Signal may be unavailable on this platform. */
    }
  }
  await stop.future;
  for (final subscription in subscriptions) {
    await subscription.cancel();
  }
  await server.close();
}
