import 'dart:convert';

import 'package:serverdeck_locald/bootstrap/discovery.dart';
import 'package:serverdeck_windows/dpapi.dart';
import 'package:serverdeck_windows/security.dart';
import 'package:test/test.dart';

final build = '${'a' * 40}+Debug+${'b' * 64}';
void main() {
  test(
    'discovery owns random token and preserves generation through readiness',
    () async {
      final sid = currentUserSid();
      final first = await DiscoveryDescriptor.create(
        ownerSid: sid,
        buildId: build,
        serverPid: 42,
      );
      final second = await DiscoveryDescriptor.create(
        ownerSid: sid,
        buildId: build,
        serverPid: 42,
      );
      try {
        expect(first.generation, isNot(second.generation));
        expect(first.bootstrapToken, isNot(second.bootstrapToken));
        expect(first.workspaceId, isNull);
        final snapshot = first.bootstrapToken;
        snapshot[0] ^= 255;
        expect(first.bootstrapToken, isNot(snapshot));
        final ready = first.withWorkspace(
          '12345678-1234-4234-9234-123456789abc',
        );
        try {
          expect(ready.generation, first.generation);
          expect(ready.bootstrapToken, first.bootstrapToken);
          expect(ready.workspaceId, '12345678-1234-4234-9234-123456789abc');
          first.close();
          expect(first.encode, throwsStateError);
          expect(() => first.bootstrapToken, throwsStateError);
          expect(ready.bootstrapToken, hasLength(32));
        } finally {
          ready.close();
        }
      } finally {
        first.close();
        second.close();
      }
    },
  );

  test(
    'real CurrentUser discovery protection is strict and entropy-bound',
    () async {
      final sid = currentUserSid();
      final descriptor = await DiscoveryDescriptor.create(
        ownerSid: sid,
        buildId: build,
        serverPid: 42,
      );
      final custody = DiscoveryCustody(DpapiProtection(), sid);
      try {
        final protected = await custody.protect(descriptor);
        final opened = await custody.unprotect(protected, build);
        try {
          expect(opened.encode(), descriptor.encode());
        } finally {
          opened.close();
        }
        await expectLater(
          DiscoveryCustody(
            DpapiProtection(),
            '$sid-99',
          ).unprotect(protected, build),
          throwsStateError,
        );
        await expectLater(
          custody.unprotect(protected, '${'c' * 40}+Debug+${'b' * 64}'),
          throwsStateError,
        );
        final json = jsonDecode(
          utf8.decode(descriptor.encode()),
        ) as Map<String, dynamic>;
        for (final change in <Map<String, Object?>>[
          {'format': 2},
          {'apiMajor': 2},
          {'apiMinor': 1},
          {'rootKey': 'forbidden'},
          {'workspaceSlot': 'other'},
          {'bootstrapToken': '${json['bootstrapToken']}='},
          {'pipeNames': List<String>.filled(8, r'\\.\pipe\foreign')},
          {'generation': 'invalid'},
          {'serverPid': 0},
          {'workspaceId': 'invalid'},
        ]) {
          await expectLater(
            DiscoveryDescriptor.decode(
              utf8.encode(jsonEncode({...json, ...change})),
              ownerSid: sid,
              expectedBuildId: build,
            ),
            throwsStateError,
          );
        }
        await expectLater(
          custody.unprotect(List<int>.filled(16385, 0), build),
          throwsStateError,
        );
      } finally {
        descriptor.close();
      }
    },
  );
}
