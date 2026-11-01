import 'dart:convert';

import 'package:serverdeck_engine/remote/direct_ssh.dart';
import 'package:serverdeck_engine/remote/direct_ssh_apt_metadata.dart';
import 'package:test/test.dart';

final at = DateTime.utc(2026, 11, 1, 0, 5);
final signer = '1' * 40, primary = '2' * 40, checksum = 'a' * 64;
String release({
  String date = 'Sun, 01 Nov 2026 00:00:00 UTC',
  String? expiry = 'Sun, 01 Nov 2026 00:20:00 UTC',
  String? hashes,
}) =>
    'Origin: RAM repository\nDate: $date\n'
    '${expiry == null ? '' : 'Valid-Until: $expiry\n'}'
    'SHA256:\n ${hashes ?? '$checksum 123 main/binary-amd64/Packages'}\n';
String signature({
  String? hash,
  String? date,
  String? keyId,
  String? issued,
  String? expiry,
}) =>
    '[GNUPG:] NEWSIG\n'
    '[GNUPG:] KEY_CONSIDERED $primary 0\n'
    '[GNUPG:] GOODSIG ${keyId ?? signer.substring(24)} RAM signer\n'
    '[GNUPG:] VALIDSIG $signer ${date ?? '2026-11-01'} '
    '${issued ?? '${DateTime.utc(2026, 11, 1).millisecondsSinceEpoch ~/ 1000}'} '
    '${expiry ?? '0'} 4 0 22 ${hash ?? '8'} 01 $primary\n';
Matcher rejected([String code = 'QUALIFICATION_REQUIRED']) => throwsA(
  isA<DirectSshFailure>().having((error) => error.code, 'safe code', code),
);

void main() {
  test('bounded Deb822 folds continuations, rejects case aliases and freezes facts', () {
    final facts = DirectAptDeb822.parse(
      'Name: first\nDescription: a\n b\n\tc\n\nName: second\n',
    );
    expect(facts.first['description'], 'a\nb\nc');
    expect(() => facts.add({}), throwsUnsupportedError);
    expect(() => facts.first['name'] = 'other', throwsUnsupportedError);
    expect(() => DirectAptDeb822.parse('Name: one\nNAME: two\n'), rejected());
    expect(() => DirectAptDeb822.parse(' continuation\n'), rejected());
    expect(() => DirectAptDeb822.parse('Name: a\rb'), rejected());
    expect(() => DirectAptDeb822.parse('Name: a\u0000b'), rejected());
    expect(
      () => DirectAptDeb822.parse('Name: a\n\nName: b', maximumStanzas: 1),
      rejected('RESOURCE_LIMIT'),
    );
    expect(
      () => DirectAptDeb822.parse('Name: ' + 'x' * 8193),
      rejected('RESOURCE_LIMIT'),
    );
    expect(
      DirectAptDeb822.parse(
        '# comment\nName: yes',
        comments: true,
      ).single['name'],
      'yes',
    );
    expect(() => DirectAptDeb822.parse('# comment\nName: yes'), rejected());
  });
  test(
    'Release checksum ledger accepts 16384 rows and refuses the next row',
    () {
      final hashes = List.generate(
        16384,
        (index) => '$checksum 123 main/binary-amd64/Packages$index',
      ).join('\n ');
      final parsed = DirectAptReleaseFields.parse(
        release(hashes: hashes),
        now: at,
      );
      expect(parsed.indexes.length, 16384);
      expect(
        parsed.matchesIndex('main/binary-amd64/Packages16383', checksum, 123),
        isTrue,
      );
      expect(
        () => DirectAptReleaseFields.parse(
          release(hashes: '$hashes\n $checksum 123 main/binary-amd64/overflow'),
          now: at,
        ),
        rejected('RESOURCE_LIMIT'),
      );
    },
  );
  test('Release fields bind exact payload and exact index hash AND size', () {
    final parsed = DirectAptReleaseFields.parse(release(), now: at);
    expect(parsed.published, DateTime.utc(2026, 11, 1));
    expect(parsed.expires, DateTime.utc(2026, 11, 1, 0, 20));
    expect(
      parsed.matchesIndex('main/binary-amd64/Packages', checksum, 123),
      isTrue,
    );
    expect(
      parsed.matchesIndex('main/binary-amd64/Packages', checksum, 124),
      isFalse,
    );
    expect(
      parsed.matchesIndex('universe/binary-amd64/Packages', checksum, 123),
      isFalse,
    );
    expect(
      parsed.matchesIndex('main/binary-amd64/Packages', 'b' * 64, 123),
      isFalse,
    );
    final changed = DirectAptReleaseFields.parse(
      release().replaceFirst('RAM', 'OTHER'),
      now: at,
    );
    expect(changed.payloadDigest, isNot(parsed.payloadDigest));
    expect(parsed.toString(), isNot(contains('RAM repository')));
    expect(() => parsed.indexes.clear(), throwsUnsupportedError);
  });
  test('signed expiry/future boundaries and explicit no-expiry immutable base fields', () {
    expect(
      () => DirectAptReleaseFields.parse(
        release(),
        now: DateTime.utc(2026, 11, 1, 0, 20),
      ),
      rejected(),
    );
    expect(
      () => DirectAptReleaseFields.parse(
        release(expiry: 'Sun, 01 Nov 2026 00:00:00 UTC'),
        now: at,
      ),
      rejected(),
    );
    expect(
      DirectAptReleaseFields.parse(
        release(date: 'Sun, 01 Nov 2026 00:10:00 UTC'),
        now: at,
      ),
      isNotNull,
    );
    expect(
      () => DirectAptReleaseFields.parse(
        release(date: 'Sun, 01 Nov 2026 00:10:01 UTC'),
        now: at,
      ),
      rejected(),
    );
    expect(
      DirectAptReleaseFields.parse(
        release(expiry: null),
        now: DateTime.utc(2030),
      ).expires,
      isNull,
    );
    expect(
      () => DirectAptReleaseFields.parse(release(expiry: ''), now: at),
      rejected(),
    );
    expect(
      () => DirectAptReleaseFields.parse(
        release(date: 'Mon, 01 Nov 2026 00:00:00 UTC'),
        now: at,
      ),
      rejected(),
    );
    expect(
      () => DirectAptReleaseFields.parse(
        release(date: 'Tue, 31 Nov 2026 00:00:00 UTC'),
        now: at,
      ),
      rejected(),
    );
    expect(
      DirectAptReleaseFields.parse(
        release(date: 'Sun, 01 Nov 2026 01:00:00 +0100'),
        now: at,
      ).published,
      DateTime.utc(2026, 11, 1),
    );
    expect(
      () => DirectAptReleaseFields.parse(
        release() + 'date: Sun, 01 Nov 2026 00:00:00 UTC\n',
        now: at,
      ),
      rejected(),
    );
  });
  test(
    'malformed and traversal checksum entries cannot name a release index',
    () {
      for (final path in [
        '/Packages',
        '../Packages',
        'a/../Packages',
        'a//Packages',
        'a/./Packages',
        'a/Packages/',
        r'a\Packages',
        r'a/$(id)',
      ]) {
        expect(
          () => DirectAptReleaseFields.parse(
            release(hashes: '$checksum 123 $path'),
            now: at,
          ),
          rejected(),
        );
      }
      for (final line in [
        '$checksum -1 Packages',
        '$checksum 01 Packages',
        '$checksum 536870913 Packages',
        'bad 123 Packages',
        '$checksum 123 Packages\n $checksum 123 Packages',
        '',
      ]) {
        expect(
          () => DirectAptReleaseFields.parse(release(hashes: line), now: at),
          rejected(),
        );
      }
    },
  );
  test('gpgv status parser records signer/subkey pins without claiming crypto authority', () {
    expect(DirectAptSignatureFields.parse(signature(), now: at).signers, [
      signer,
    ]);
    expect(
      DirectAptSignatureFields.parse(
        signature(),
        now: at,
        allowedFingerprints: {primary},
      ).signers,
      [signer],
    );
    expect(
      DirectAptSignatureFields.parse(
        signature(),
        now: at,
        allowedFingerprints: {signer + '!'},
      ).signers,
      [signer],
    );
    expect(
      () => DirectAptSignatureFields.parse(
        signature(),
        now: at,
        allowedFingerprints: {primary + '!'},
      ),
      rejected(),
    );
    expect(
      () => DirectAptSignatureFields.parse(
        signature(),
        now: at,
        allowedFingerprints: {'3' * 40},
      ),
      rejected(),
    );
    final parsed = DirectAptSignatureFields.parse(signature(), now: at);
    expect(() => parsed.signers.clear(), throwsUnsupportedError);
    expect(parsed.toString(), isNot(contains('RAM signer')));
  });
  test(
    'signature failure/revocation/weak digest/expiry/partial status refuse',
    () {
      for (final status in [
        'BADSIG',
        'ERRSIG',
        'NO_PUBKEY',
        'EXPSIG',
        'EXPKEYSIG',
        'REVKEYSIG',
        'FAILURE',
        'UNKNOWN',
      ]) {
        expect(
          () => DirectAptSignatureFields.parse(
            signature() + '[GNUPG:] $status bad\n',
            now: at,
          ),
          rejected(),
        );
      }
      for (final text in [
        signature(hash: '2'),
        signature(date: '2026-99-99'),
        signature(keyId: signer.substring(23)),
        signature(issued: '99999999999'),
        signature(expiry: '${at.millisecondsSinceEpoch ~/ 1000}'),
        signature()
            .split('\n')
            .where((row) => !row.contains('GOODSIG'))
            .join('\n'),
        signature()
            .split('\n')
            .where((row) => !row.contains('VALIDSIG'))
            .join('\n'),
        signature() + signature(),
        'PRIVATE_TEXT\n' + signature(),
      ]) {
        expect(() => DirectAptSignatureFields.parse(text, now: at), rejected());
      }
      expect(
        () => DirectAptSignatureFields.parse('x' * (64 * 1024 + 1), now: at),
        rejected('RESOURCE_LIMIT'),
      );
    },
  );
  test('payload limits apply before parsing peer-controlled metadata', () {
    expect(
      () => DirectAptReleaseFields.parse('x' * (4 * 1024 * 1024 + 1), now: at),
      rejected('RESOURCE_LIMIT'),
    );
    expect(
      () => DirectAptDeb822.parse(utf8.decode([0xff], allowMalformed: true)),
      rejected(),
    );
  });
  test('separate signature groups cannot exchange good/valid records', () {
    final split = signature().replaceFirst(
      '[GNUPG:] VALIDSIG',
      '[GNUPG:] NEWSIG\n[GNUPG:] VALIDSIG',
    );
    expect(() => DirectAptSignatureFields.parse(split, now: at), rejected());
    expect(
      () => DirectAptSignatureFields.parse(
        signature().replaceFirst('[GNUPG:] NEWSIG\n', ''),
        now: at,
      ),
      rejected(),
    );
    expect(
      () => DirectAptSignatureFields.parse(
        signature() + '[GNUPG:] NEWSIG\n',
        now: at,
      ),
      rejected(),
    );
    expect(
      DirectAptSignatureFields.parse(
        signature() + '[GNUPG:] KEYEXPIRED 1\n',
        now: at,
      ).signers,
      [signer],
    );
    for (final invalid in [
      'KEY_CONSIDERED bad 0',
      'KEY_CONSIDERED $primary 99',
      'TRUST_FULLY 1 pgp',
      'TRUST_UNDEFINED 0 PRIVATE_MODEL',
      'SIG_ID bad bad bad',
    ]) {
      expect(
        () => DirectAptSignatureFields.parse(
          signature() + '[GNUPG:] $invalid\n',
          now: at,
        ),
        rejected(),
      );
    }
  });
}
