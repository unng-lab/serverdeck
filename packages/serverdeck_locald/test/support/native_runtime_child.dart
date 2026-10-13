import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/native_runtime.dart';

Future<void> main(List<String> args) async {
  final root = args.single;
  final verified = await initializeNativeRuntime(root);
  if (verified.appRoot != root ||
      (await initializeNativeRuntime(root)).buildId != verified.buildId) {
    throw StateError('FIXTURE_ASSERTION_FAILED');
  }
  File(p.join(root, 'serverdeck.exe')).writeAsBytesSync([8]);
  try {
    await initializeNativeRuntime(root);
  } on StateError catch (error) {
    if (error.message == 'INCOMPATIBLE') return;
    rethrow;
  }
  throw StateError('FIXTURE_ASSERTION_FAILED');
}
