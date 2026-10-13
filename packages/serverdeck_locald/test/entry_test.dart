import 'package:path/path.dart' as p;
import 'package:serverdeck_locald/bootstrap/entry.dart';
import 'package:test/test.dart';

void main() {
  test('accepts exact fixed workspace contract in either option order', () {
    final root = p.absolute('fixture-bundle');
    for (final args in [
      ['--workspace', 'default', '--app-root', root],
      ['--app-root', root, '--workspace', 'default'],
    ]) {
      expect(LocaldArguments.parse(args).appRoot, p.normalize(root));
    }
  });
  test(
    'rejects ambiguous, extra, missing, secret and alternate namespace args',
    () {
      final root = p.absolute('fixture-bundle');
      for (final args in <List<String>>[
        [],
        ['--workspace', 'default'],
        ['--workspace', 'default', '--app-root'],
        ['--workspace', 'other', '--app-root', root],
        ['--workspace', 'default', '--app-root', 'relative'],
        ['--workspace', 'default', '--app-root', ''],
        ['--workspace', 'default', '--app-root', '$root\u0000'],
        ['--workspace', 'default', '--app-root', '/${'a' * 32768}'],
        ['--workspace', 'default', '--workspace', 'default'],
        ['--app-root', root, '--app-root', root],
        ['--workspace=default', '', '--app-root', root],
        ['--token', 'synthetic-test-value', '--app-root', root],
        ['--workspace', 'default', '--app-root', root, '--test-only', 'true'],
      ]) {
        expect(
          () => LocaldArguments.parse(args),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'safe code',
              'PREREQUISITE_UNAVAILABLE',
            ),
          ),
        );
      }
    },
  );
}
