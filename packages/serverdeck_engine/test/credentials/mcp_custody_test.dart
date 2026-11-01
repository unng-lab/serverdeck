import 'package:serverdeck_engine/credentials/mcp_credentials.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-123456789abc';
const grant = '12345678-1234-4234-9234-123456789abd';
const secret = '12345678-1234-4234-9234-123456789abe';
const other = '12345678-1234-4234-9234-123456789abf';
McpCredentialBinding binding({String grantId = grant}) => McpCredentialBinding(
  workspaceId: workspace,
  grantId: grantId,
  secretRef: secret,
  ownerSid: 'S-1-5-21-1-2-3-1001',
  issuedAt: '2026-10-30T10:00:00.000Z',
);
Matcher blocked() => throwsA(
  isA<StateError>().having(
    (error) => error.message,
    'safe category',
    'STORAGE_BLOCKED',
  ),
);

/// Synthetic RAM-only vault. It is not an encryption implementation or OS probe.
final class Vault implements UserProtection {
  final blobs = <int, List<int>>{};
  List<int>? borrowedClear, borrowedRecovered;
  bool unavailable = false;
  @override
  Future<List<int>> protect(List<int> clear, List<int> entropy) async {
    borrowedClear = clear;
    if (unavailable) throw StateError('private-provider-message');
    final id = blobs.length + 1;
    blobs[id] = List<int>.of(clear);
    return [id];
  }

  @override
  Future<List<int>> unprotect(List<int> ciphertext, List<int> entropy) async {
    if (unavailable ||
        ciphertext.length != 1 ||
        !blobs.containsKey(ciphertext.single)) {
      throw StateError('private-provider-message');
    }
    return borrowedRecovered = List<int>.of(blobs[ciphertext.single]!);
  }

  void dispose() {
    for (final clear in blobs.values) {
      clear.fillRange(0, clear.length, 0);
    }
    blobs.clear();
  }
}

void main() {
  test('same identity reopens the same key while independent issuance stays distinct', () async {
    final vault = Vault(), custody = McpCredentialCustody(vault);
    final issued = await custody.create(binding());
    final independent = await custody.create(binding());
    final reopened = await custody.open(issued.wrapper, binding());
    try {
      final proof = await issued.key.mac([1, 3, 5]);
      expect(await reopened.verify([1, 3, 5], proof), isTrue);
      expect(await independent.key.verify([1, 3, 5], proof), isFalse);
      expect(await reopened.verify([1, 3, 6], proof), isFalse);
      expect(vault.borrowedClear, everyElement(0));
      expect(vault.borrowedRecovered, everyElement(0));
      expect(() => issued.wrapper[0] = 99, throwsUnsupportedError);
    } finally {
      issued.key.close();
      independent.key.close();
      reopened.close();
      vault.dispose();
    }
  });

  test(
    'a different grant cannot reuse a protected credential or a closed handle',
    () async {
      final vault = Vault(), custody = McpCredentialCustody(vault);
      final issued = await custody.create(binding());
      try {
        await expectLater(
          custody.open(issued.wrapper, binding(grantId: other)),
          blocked(),
        );
        issued.key.close();
        await expectLater(issued.key.mac([1]), blocked());
        expect(vault.borrowedRecovered, everyElement(0));
      } finally {
        issued.key.close();
        vault.dispose();
      }
    },
  );

  test('unavailable protection refuses persistence and never exposes provider text', () async {
    final vault = Vault()..unavailable = true;
    final custody = McpCredentialCustody(vault);
    await expectLater(custody.create(binding()), blocked());
    expect(vault.blobs, isEmpty);
    expect(vault.borrowedClear, everyElement(0));
    await expectLater(custody.open([1], binding()), blocked());
    vault.dispose();
  });
}
