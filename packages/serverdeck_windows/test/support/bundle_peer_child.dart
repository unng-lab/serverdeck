import 'dart:io';

Future<void> main() async {
  stdout.writeln('READY');
  await stdout.flush();
  await stdin.drain<void>();
}
