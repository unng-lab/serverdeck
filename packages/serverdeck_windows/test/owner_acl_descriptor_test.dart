import 'dart:ffi';

import 'package:serverdeck_windows/security.dart';

import 'package:test/test.dart';

void main() {
  bool matches(String sddl, String sid, String rights) {
    final attributes = SecurityAttributes(sddl);
    try {
      return matchesOwnerOnlyAclDescriptor(
        attributes.pointer.ref.lpSecurityDescriptor,
        sid,
        rights,
      );
    } finally {
      attributes.close();
    }
  }

  test('native SID aliases preserve exact owner and protected ACL', () {
    final current = currentUserSid();
    final sids = [current, 'S-1-5-18', 'S-1-5-19', 'S-1-5-20'];
    if (current.startsWith('S-1-5-21-')) {
      sids.add('${current.substring(0, current.lastIndexOf('-') + 1)}500');
    }
    for (final sid in sids) {
      for (final rights in ['FA', '0x1f0001', '0x120083']) {
        for (final acl in [
          '(A;;$rights;;;$sid)(A;;$rights;;;SY)',
          '(A;;$rights;;;SY)(A;;$rights;;;$sid)',
        ]) {
          expect(matches('O:${sid}D:P$acl', sid, rights), isTrue);
        }
      }
    }
  }, testOn: 'windows');

  test('canonical comparison refuses owner flags masks and extra grants', () {
    final sid = currentUserSid();
    final other = sid == 'S-1-5-18' ? 'S-1-5-19' : 'S-1-5-18';
    for (final sddl in [
      'O:${other}D:P(A;;FA;;;$sid)(A;;FA;;;SY)',
      'O:${sid}D:(A;;FA;;;$sid)(A;;FA;;;SY)',
      'O:${sid}D:P(A;;FA;;;$sid)(A;;FA;;;SY)(A;;FR;;;BU)',
      'O:${sid}D:P(A;;FR;;;$sid)(A;;FA;;;SY)',
      'O:${sid}D:P(A;OI;FA;;;$sid)(A;;FA;;;SY)',
      'O:${sid}D:NO_ACCESS_CONTROL',
    ]) {
      expect(matches(sddl, sid, 'FA'), isFalse);
    }
    final valid = ownerOnlySddl(sid);
    expect(matches(valid, other, 'FA'), isFalse);
    expect(matches(valid, sid, '0x1f0001'), isFalse);
    expect(matches(valid, sid, 'invalid'), isFalse);
    expect(matches(valid, 'invalid', 'FA'), isFalse);
  }, testOn: 'windows');
}
