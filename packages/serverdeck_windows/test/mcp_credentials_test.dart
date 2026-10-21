import 'dart:async';
import 'dart:convert';

import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/mcp_credentials.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

const workspace = '12345678-1234-4234-9234-123456789abc';
const grant = '12345678-1234-4234-9234-123456789abd';
const secret = '12345678-1234-4234-9234-123456789abe';
const other = '12345678-1234-4234-9234-123456789abf';
const issued = '2026-10-21T10:00:00.000Z';
const sid = 'S-1-5-21-1-2-3-1001';
McpCredentialBinding binding({
  String workspaceId = workspace,
  String grantId = grant,
  String secretRef = secret,
  String ownerSid = sid,
  String issuedAt = issued,
}) => McpCredentialBinding(
  workspaceId: workspaceId,
  grantId: grantId,
  secretRef: secretRef,
  ownerSid: ownerSid,
  issuedAt: issuedAt,
);
final blocked = throwsA(
  isA<StateError>().having((e) => e.message, 'safe code', 'STORAGE_BLOCKED'),
);

class Provider implements UserProtection {
  List<int>? protectedInput, recoveredInput, entropy;
  List<int>? overrideClear;
  List<int> protectedOutput = [1, 2, 3];
  bool failProtect = false, failOpen = false;
  Object? openError;
  bool readonlyRecovered = false;
  Completer<void>? pause;
  @override
  Future<List<int>> protect(List<int> cleartext, List<int> additional) async {
    protectedInput = cleartext;
    entropy = List.of(additional);
    final copy = List<int>.of(cleartext);
    if (pause != null) await pause!.future;
    if (failProtect) throw StateError('PRIVATE_PROVIDER_INPUT');
    overrideClear ??= copy;
    return protectedOutput;
  }

  @override
  Future<List<int>> unprotect(
    List<int> ciphertext,
    List<int> additional,
  ) async {
    if (openError != null) throw openError!;
    final actual = List<int>.of(ciphertext);
    if (pause != null) await pause!.future;
    if (failOpen || actual.toString() != '[1, 2, 3]') {
      throw StateError('PRIVATE_PROVIDER_INPUT');
    }
    recoveredInput = readonlyRecovered
        ? List<int>.unmodifiable(overrideClear!)
        : List.of(overrideClear!);
    return recoveredInput!;
  }
}

void main() {
  test('envelope plaintext limit captures the encoded buffer before refusing protection', () async {
    for (final digits in [3771, 3772, 3773, 3800]) {
      final provider = Provider();
      final custody = McpCredentialCustody(provider);
      final identity = binding(ownerSid: 'S-1-5-${'1' * digits}');
      if (digits <= 3772) {
        final created = await custody.create(identity);
        created.key.close();
        expect(provider.protectedInput!.length, digits + 324);
        expect(provider.protectedInput, everyElement(0));
      } else {
        await expectLater(custody.create(identity), blocked);
        expect(provider.protectedInput, isNull);
      }
    }
  });
  test('independent HMAC vector and provider errors never masquerade as format incompatibility', () async {
    final provider = Provider();
    final custody = McpCredentialCustody(provider);
    final created = await custody.create(binding());
    created.key.close();
    final document = jsonDecode(utf8.decode(provider.overrideClear!)) as Map;
    document['clientSecret'] = base64.encode(List.filled(32, 0));
    provider.overrideClear = utf8.encode(jsonEncode(document));
    final opened = await custody.open([1, 2, 3], binding());
    try {
      final proof = await opened.mac([7, 8, 9]);
      expect(
        proof.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '10d7a272cd65b8702733c9bd617e4ff7942cbde0eb750fbca1a41b8ecd851ca1',
      );
    } finally {
      opened.close();
    }
    provider.openError = StateError('INCOMPATIBLE');
    await expectLater(custody.open([1, 2, 3], binding()), blocked);
    provider.openError = null;
    provider.readonlyRecovered = true;
    await expectLater(custody.open([1, 2, 3], binding()), blocked);
    for (final invalid in [
      <int>[],
      [256],
      [-1],
      List.filled(16385, 1),
    ]) {
      provider.protectedOutput = invalid;
      await expectLater(custody.create(binding()), blocked);
      expect(provider.protectedInput, everyElement(0));
    }
  });
  test(
    'real DPAPI random keys and exact identities, MAC agreement and corruption',
    () async {
      final identity = binding(ownerSid: currentUserSid());
      final custody = McpCredentialCustody(DpapiProtection());
      final first = await custody.create(identity);
      final second = await custody.create(identity);
      final opened = await custody.open(first.wrapper, identity);
      try {
        final proof = await first.key.mac([7, 8, 9]);
        expect(await opened.verify([7, 8, 9], proof), isTrue);
        expect(await second.key.verify([7, 8, 9], proof), isFalse);
        expect(await opened.verify([7, 8, 10], proof), isFalse);
        expect(() => first.wrapper[0] = 0, throwsUnsupportedError);
        for (final wrong in [
          binding(workspaceId: other, ownerSid: currentUserSid()),
          binding(grantId: other, ownerSid: currentUserSid()),
          binding(secretRef: other, ownerSid: currentUserSid()),
          binding(ownerSid: '${currentUserSid()}-1'),
          binding(
            ownerSid: currentUserSid(),
            issuedAt: '2026-10-21T10:00:00.001Z',
          ),
        ]) {
          await expectLater(custody.open(first.wrapper, wrong), blocked);
        }
        final damaged = List<int>.of(first.wrapper);
        damaged[damaged.length ~/ 2] ^= 1;
        await expectLater(custody.open(damaged, identity), blocked);
        first.key.close();
        first.key.close();
        await expectLater(first.key.mac([1]), blocked);
      } finally {
        first.key.close();
        second.key.close();
        opened.close();
      }
    },
    testOn: 'windows',
  );

  test('strict recovered fields, versions, duplicate JSON and canonical 32byte secret', () async {
    final provider = Provider();
    final custody = McpCredentialCustody(provider);
    final created = await custody.create(binding());
    created.key.close();
    final valid = jsonDecode(
      utf8.decode(provider.overrideClear!),
    ) as Map<String, dynamic>;
    for (final edit in <void Function(Map<String, dynamic>)>[
      (v) => v['extra'] = 'PRIVATE',
      (v) => v.remove('grantId'),
      (v) => v['grantId'] = other,
      (v) => v['workspaceId'] = other,
      (v) => v['secretRef'] = other,
      (v) => v['ownerSid'] = '$sid-2',
      (v) => v['issuedAt'] = '2026-10-21T10:00:00.001Z',
      (v) => v['product'] = 'wrong',
      (v) => v['format'] = '1',
      (v) => v['clientSecret'] = base64.encode(List.filled(31, 0)),
      (v) => v['clientSecret'] = base64.encode(List.filled(33, 0)),
      (v) =>
          v['clientSecret'] = (v['clientSecret'] as String).replaceAll('=', ''),
      (v) => v['clientSecret'] = 'PRIVATE_INVALID',
      (v) => v['clientSecret'] = '${'A' * 42}B=', // Nonzero unused pad bits.
      (v) => v['clientSecret'] = '${'A' * 42}!=', // Late invalid character.
      (v) => v['clientSecret'] = '${'A' * 41}-A=', // URL alphabet.
      (v) => v['clientSecret'] = '${'A' * 43}%3D', // Escaped padding.
    ]) {
      final value = Map<String, dynamic>.of(valid);
      edit(value);
      provider.overrideClear = utf8.encode(jsonEncode(value));
      await expectLater(custody.open([1, 2, 3], binding()), blocked);
      expect(provider.recoveredInput, everyElement(0));
    }
    provider.overrideClear = utf8.encode(jsonEncode({...valid, 'format': 2}));
    await expectLater(
      custody.open([1, 2, 3], binding()),
      throwsA(
        isA<StateError>().having((e) => e.message, 'code', 'INCOMPATIBLE'),
      ),
    );
    provider.overrideClear = utf8.encode('{"format":1,"format":1}');
    await expectLater(custody.open([1, 2, 3], binding()), blocked);
    for (final clear in [
      <int>[],
      [255],
      List.filled(4097, 32),
      [256],
    ]) {
      provider.overrideClear = clear;
      await expectLater(custody.open([1, 2, 3], binding()), blocked);
    }
  });

  test(
    'provider failures, input bounds, async snapshots and buffer disposal',
    () async {
      final provider = Provider();
      final custody = McpCredentialCustody(provider);
      final created = await custody.create(binding());
      expect(provider.protectedInput, everyElement(0));
      expect(jsonDecode(utf8.decode(provider.entropy!)), {
        'purpose': 'serverdeck-next-mcp-client-v1',
        'workspaceId': workspace,
        'grantId': grant,
        'secretRef': secret,
        'ownerSid': sid,
        'issuedAt': issued,
      });
      for (final bytes in [
        <int>[],
        [256],
        [-1],
        List.filled(16385, 0),
      ]) {
        await expectLater(custody.open(bytes, binding()), blocked);
      }
      provider.pause = Completer<void>();
      final wrapper = [1, 2, 3];
      final opening = custody.open(wrapper, binding());
      wrapper[0] = 99;
      provider.pause!.complete();
      final opened = await opening;
      expect(provider.recoveredInput, everyElement(0));
      for (final bytes in [
        <int>[],
        [256],
        [-1],
        List.filled(4097, 0),
      ]) {
        await expectLater(opened.mac(bytes), blocked);
      }
      final transcript = [9, 8, 7];
      final original = List<int>.of(transcript);
      final proofFuture = opened.mac(transcript);
      transcript[0] = 1;
      final proof = await proofFuture;
      final expected = List<int>.of(proof);
      final verification = opened.verify(original, expected);
      expected[0] ^= 1;
      expect(await verification, isTrue);
      await expectLater(opened.verify(original, [1]), blocked);
      await expectLater(opened.verify(original, List.filled(32, 256)), blocked);
      final pending = opened.mac([1]);
      opened.close();
      await expectLater(pending, blocked);
      provider.pause = null;
      provider.failProtect = true;
      await expectLater(custody.create(binding()), blocked);
      expect(provider.protectedInput, everyElement(0));
      provider.failOpen = true;
      await expectLater(custody.open([1, 2, 3], binding()), blocked);
      created.key.close();
    },
  );

  test(
    'binding rejects noncanonical identity and time before provider use',
    () {
      for (final make in <McpCredentialBinding Function()>[
        () => binding(workspaceId: 'INVALID_PRIVATE'),
        () => binding(grantId: 'bad'),
        () => binding(secretRef: 'bad'),
        () => binding(ownerSid: 'bad'),
        () => binding(issuedAt: '2026-10-21T10:00:00Z'),
      ]) {
        expect(make, blocked);
      }
    },
  );
}
