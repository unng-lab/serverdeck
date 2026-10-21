import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/process.dart';
import 'package:test/test.dart';

import '../support/native_artifact.dart';
import '../support/grant_transaction_scenarios.dart' show grantBoundaryModes;
import '../support/grant_failure_scenarios.dart' show grantFaultModes;
import '../support/grant_key_loss_scenarios.dart' show grantKeyLossModes;
import '../support/grant_publication_scenarios.dart'
    show grantPublicationFaultModes;

void main() {
  for (final mode in [
    'good',
    'empty',
    'stale',
    'revoked',
    'reservation',
    'reservation-race',
    'grant-basic',
    ...grantBoundaryModes,
    ...grantFaultModes,
    ...grantKeyLossModes,
    ...grantPublicationFaultModes,
    'grant-capacity',
    'manifest-malformed',
    'manifest-foreign',
    'manifest-schema1',
    'native-schema1',
    'bundle',
    'wrapper',
    'creating',
    'upgrading',
    'acl-product',
    'acl-version',
    'acl-parent',
    'acl-active',
    'acl-database',
    'acl-lock',
    'junction',
    'link-database',
    'link-lock',
    'closed-key',
    'closed-lease',
    'close-false',
    'open-throw',
    'wrong-schema',
    'bad-graph',
    'bad-native-id',
    'second-corrupt',
    'second-lookup',
  ]) {
    test(
      'actual owned operational native open $mode',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'serverdeck-operational-snapshot-',
        );
        final path = p.normalize(p.absolute(root.path));
        checkRoot(path);
        Process? child;
        try {
          final bundle = Directory(p.join(path, 'bundle'))..createSync();
          File(p.join(bundle.path, 'serverdeck.exe'))
              .writeAsBytesSync([1, 2, 3]);
          File(p.join(bundle.path, 'locald.exe')).writeAsBytesSync([4, 5, 6]);
          final dll = p.join(bundle.path, 'libisar.dll');
          File(nativeArtifactForTest()).copySync(dll);
          File(p.join(bundle.path, 'foundation.manifest.json'))
              .writeAsStringSync(
                jsonEncode({
                  'format': 1,
                  'buildId': '${'a' * 40}+Debug+${'b' * 64}',
                  'configuration': 'Debug',
                  'testOnly': false,
                  'appRoot': bundle.path,
                  'sha256': {
                    for (final name in [
                      'serverdeck.exe',
                      'locald.exe',
                      'libisar.dll',
                    ])
                      name: fileSha256(p.join(bundle.path, name)),
                  },
                }),
              );
          child = await Process.start(
            p.join(p.dirname(Platform.resolvedExecutable), 'dartvm.exe'),
            [
              if (grantFaultModes.contains(mode) &&
                  mode != 'grant-probe-disabled')
                '-DSERVERDECK_TEST_GRANT_WRITE_PROBES=true',
              if (grantPublicationFaultModes.contains(mode) &&
                  mode != 'grant-pointer-disabled')
                '-DSERVERDECK_TEST_MCP_FILE_PROBES=true',
              'test/support/operational_snapshot_child.dart',
              path,
              dll,
              'owned-$mode',
              bundle.path,
            ],
          );
          final output = child.stdout.transform(utf8.decoder).map((chunk) {
            if (mode == 'grant-capacity') stdout.write(chunk);
            return chunk;
          }).join();
          final errors = child.stderr.transform(utf8.decoder).join();
          final code = await child.exitCode.timeout(
            Duration(seconds: mode == 'grant-capacity' ? 900 : 60),
          );
          expect(
            code,
            0,
            reason: await errors.timeout(const Duration(seconds: 5)),
          );
          expect(
            await output.timeout(const Duration(seconds: 5)),
            contains(
              {
                        'good',
                        'empty',
                        'stale',
                        'revoked',
                        'reservation',
                        'reservation-race',
                        'grant-basic',
                      }.contains(mode) ||
                      grantBoundaryModes.contains(mode) ||
                      grantFaultModes.contains(mode) ||
                      grantKeyLossModes.contains(mode) ||
                      grantPublicationFaultModes.contains(mode) ||
                      mode == 'grant-capacity'
                  ? 'OWNED_OPERATIONAL_REOPEN_RESERVATION_PROVED'
                  : 'OWNED_OPERATIONAL_REFUSAL_PROVED',
            ),
          );
        } finally {
          if (child != null) {
            child.kill();
            await child.exitCode.timeout(const Duration(seconds: 10));
          }
          checkRoot(path);
          root.deleteSync(recursive: true);
        }
      },
      testOn: 'windows',
      timeout: Timeout(Duration(seconds: mode == 'grant-capacity' ? 920 : 80)),
    );
  }
}

void checkRoot(String path) {
  if (!p.isWithin(p.normalize(p.absolute(Directory.systemTemp.path)), path) ||
      !p.basename(path).startsWith('serverdeck-operational-snapshot-'))
    throw StateError('UNSAFE_FIXTURE');
}
