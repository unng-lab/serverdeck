import 'package:serverdeck_engine/storage/row_plan.dart';
import 'package:serverdeck_engine/storage/workspace_rows.dart';
import 'package:test/test.dart';

Matcher failure(String code) => throwsA(
  isA<StateError>().having((error) => error.message, 'safe code', code),
);

void main() {
  test(
    'unchanged rows retain exact bytes and identity despite JSON spelling',
    () {
      const original = StoredRow(
        71,
        ' {"protectedBlob":"AQ==", "name":"\\u0061"}\n',
        entityId: 'first',
      );
      final input = [original];
      final result = retainRowIdentities(input, [
        const StoredRow(
          0,
          '{"name":"a","protectedBlob":"AQ=="}',
          entityId: 'first',
        ),
      ]);
      expect(identical(result.single, original), isTrue);
      expect(result.single.nativeId, 71);
      expect(result.single.payload, original.payload);
      input.clear();
      expect(result, hasLength(1));
      expect(() => result.clear(), throwsUnsupportedError);
    },
  );

  test('updates retain IDs; allocation follows previous maximum including deleted rows', () {
    const unchanged = StoredRow(2, '{"n":2}', entityId: 'unchanged');
    final result = retainRowIdentities(
      [
        const StoredRow(97, '{"n":1}', entityId: 'deleted'),
        const StoredRow(71, '{"n":1}', entityId: 'updated'),
        unchanged,
      ],
      [
        const StoredRow(999, '{"n":3}', entityId: 'new'),
        const StoredRow(0, '{"n":2}', entityId: 'updated'),
        const StoredRow(0, '{"n":2}', entityId: 'unchanged'),
      ],
    );
    expect(result.map((row) => row.nativeId), [2, 71, 98]);
    expect(result.map((row) => row.entityId), ['unchanged', 'updated', 'new']);
    expect(identical(result.first, unchanged), isTrue);
    expect(result[1].payload, '{"n":2}');
  });

  test(
    'native ID exhaustion refuses insertion but permits retained update',
    () {
      const old = StoredRow(9223372036854775807, '{"n":1}', entityId: 'old');
      expect(
        () => retainRowIdentities(
          [old],
          [const StoredRow(0, '{}', entityId: 'new')],
        ),
        failure('RESOURCE_LIMIT'),
      );
      expect(
        retainRowIdentities(
          [old],
          [const StoredRow(0, '{"n":2}', entityId: 'old')],
        ).single.nativeId,
        old.nativeId,
      );
    },
  );

  test(
    'singleton ID retained; ambiguous or corrupt raw inputs cannot be planned',
    () {
      expect(
        retainRowIdentities(
          [const StoredRow(1, '{}')],
          [const StoredRow(0, '{"revision":"1"}')],
        ).single.nativeId,
        1,
      );
      for (final before in [
        [const StoredRow(0, '{}', entityId: 'a')],
        [
          const StoredRow(1, '{}', entityId: 'a'),
          const StoredRow(1, '{}', entityId: 'b'),
        ],
        [
          const StoredRow(1, '{}', entityId: 'a'),
          const StoredRow(2, '{}', entityId: 'a'),
        ],
      ]) {
        expect(
          () => retainRowIdentities(before, []),
          failure('STORAGE_BLOCKED'),
        );
      }
      expect(
        () => retainRowIdentities([], [
          const StoredRow(0, '{}', entityId: 'a'),
          const StoredRow(0, '{}', entityId: 'a'),
        ]),
        failure('STORAGE_BLOCKED'),
      );
      expect(
        () => retainRowIdentities([], [const StoredRow(0, '{')]),
        throwsFormatException,
      );
    },
  );
}
