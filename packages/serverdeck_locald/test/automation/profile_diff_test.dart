import 'package:serverdeck_locald/automation/profile_diff.dart';
import 'package:test/test.dart';

void main() {
  test('typed ordered changes escape paths and retain null versus absence', () {
    expect(
      profileCatalogDiff(
        {
          'a/b~': [1, true, null],
          'gone': 9,
        },
        {
          'a/b~': [1, 1, null, false],
          'new': null,
        },
      ),
      {
        'changes': [
          {'op': 'replace', 'path': '/a~1b~0/1', 'before': true, 'after': 1},
          {'op': 'add', 'path': '/a~1b~0/3', 'after': false},
          {'op': 'remove', 'path': '/gone', 'before': 9},
          {'op': 'add', 'path': '/new', 'after': null},
        ],
        'truncated': false,
      },
    );
  });
  test('equal bodies produce no changes irrespective of insertion order', () {
    expect(profileCatalogDiff({'z': 1, 'a': false}, {'a': false, 'z': 1}), {
      'changes': [],
      'truncated': false,
    });
  });
  test('diff stops at its result count budget', () {
    final result = profileCatalogDiff({}, {
      for (var n = 0; n < 2100; n++) 'k$n': n,
    });
    expect((result['changes'] as List).length, 2048);
    expect(result['truncated'], true);
  });
  test('diff stops before an escaped result exceeds its byte budget', () {
    final text = '\\' * 65510;
    final result = profileCatalogDiff({'a': text}, {'b': text});
    expect(result['truncated'], true);
    expect((result['changes'] as List).length, 1);
  });
}
