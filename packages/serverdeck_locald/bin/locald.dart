import 'dart:io';

import 'package:serverdeck_locald/bootstrap/entry.dart';
import 'package:serverdeck_locald/bootstrap/trusted_entry.dart';
import 'package:serverdeck_locald/bootstrap/trusted_bootstrap.dart';

Future<void> main(List<String> arguments) async {
  final startup = Stopwatch()..start();
  try {
    final options = LocaldArguments.parse(arguments);
    final environment = await TrustedLocaldEnvironment.verify(options);
    await TrustedLocaldBootstrap(environment, () => startup.elapsed).run();
  } catch (error) {
    const safeCodes = {
      'SERVICE_UNAVAILABLE',
      'PREREQUISITE_UNAVAILABLE',
      'INCOMPATIBLE',
      'TIMEOUT',
      'STORAGE_BLOCKED',
    };
    stderr.writeln(
      error is StateError && safeCodes.contains(error.message)
          ? error.message
          : 'PREREQUISITE_UNAVAILABLE',
    );
    exitCode = 1;
  } finally {
    startup.stop();
  }
}
