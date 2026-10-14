import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/security.dart';

import 'credential_ui_markers.dart';
import 'ui_private_file_scan.dart';

Future<void> main(List<String> args) async {
  var phase = 'arguments';
  String? ownedFixture;
  try {
    check(args.length == 2);
    phase = 'fixture-name';
    final fixture = p.dirname(p.dirname(Platform.resolvedExecutable));
    check(
      RegExp(r'^foundation-ui-[a-f0-9]{32}$').hasMatch(p.basename(fixture)),
    );
    final root = p.normalize(p.absolute(args[0]));
    phase = 'profile-binding';
    check(p.equals(root, p.join(fixture, 'profile')));
    phase = 'path-safety';
    requireSafePath(fixture, root);
    ownedFixture = fixture;
    final sid = currentUserSid();
    final outputs = p.join(fixture, 'credential-output');
    final mode = args[1];
    if (mode == 'prepare') {
      createProtectedDirectory(fixture, outputs, sid);
      for (var step = 0; step < 10; step++) {
        await createProtectedEmptyFile(
          fixture,
          p.join(outputs, 'step-$step.private.txt'),
          sid,
        );
      }
      stdout.writeln('CREDENTIAL_OUTPUT_CAPTURE_PREPARED');
      return;
    }
    final negative = mode == 'negative';
    final step = int.tryParse(mode);
    check(negative || (step != null && step >= 0 && step < 10));
    final output = p.join(
      outputs,
      negative ? 'negative.private.txt' : 'step-$step.private.txt',
    );
    if (negative) {
      await writeNewProtectedFile(
        fixture,
        output,
        sid,
        utf8.encode(credentialUiPassword),
      );
    }
    Map<String, Object?> scan;
    try {
      scan = await scanUiPrivateFiles(
        root,
        [
          credentialUiPassword,
          credentialUiPassphrase,
          credentialUiCancelledPassword,
        ],
        credentialUiPem,
        outputFile: output,
        onPhase: (next) => phase = next,
      );
    } on StateError catch (error) {
      if (negative && error.message == 'PRIVATE_MARKER_FOUND') {
        stdout.writeln('CREDENTIAL_OUTPUT_SYNTHETIC_LEAK_REJECTED');
        return;
      }
      rethrow;
    }
    check(!negative);
    phase = 'original-stage-proof';
    final original = File(p.join(root, 'ui-credentials', 'step-$step.json'));
    requireSafePath(root, original.path);
    final originalBytes = await original.readAsBytes();
    final stage = StrictCodec().decode(originalBytes, maxBytes: 4096);
    check(
      stage['format'] == 1 &&
          stage['scenario'] == 'ui-credential-reopen' &&
          stage['step'] == step,
    );
    final digest = await Sha256().hash(originalBytes);
    final outputProof = p.join(outputs, 'output-step-$step.json');
    phase = 'output-proof-publication';
    await writeNewProtectedFile(
      fixture,
      outputProof,
      sid,
      utf8.encode(
        jsonEncode({
          'format': 1,
          'scenario': 'credential-output-scan',
          'step': step,
          'stageProofSha256': digest.bytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(),
          ...scan,
          'scanned': [
            'postclose-product-files',
            'completed-flutter-drive-all-streams',
          ],
          'excluded': [
            'embedded-synthetic-inputs',
            'live-uncommitted-native-files',
            'foreign-temp',
            'full-Q05',
          ],
          'fullAcceptance': false,
        }),
      ),
    );
    stdout.writeln('CREDENTIAL_OUTPUT_STEP_${step}_CLEAN_PROVED');
  } on Object catch (error) {
    if (ownedFixture != null) {
      try {
        await writeNewProtectedFile(
          ownedFixture,
          p.join(ownedFixture, 'credential-output', 'scanner-failure.json'),
          currentUserSid(),
          utf8.encode(
            jsonEncode({
              'format': 1,
              'phase': phase,
              'errorKind': error.runtimeType.toString(),
              'markerFound':
                  error is StateError &&
                  error.message == 'PRIVATE_MARKER_FOUND',
              'nativeError': error is FileSystemException
                  ? error.osError?.errorCode
                  : null,
              'fullAcceptance': false,
            }),
          ),
        );
      } on Object {
        // The first failed attempt is retained; never overwrite or expose errors.
      }
    }
    stderr.writeln('CREDENTIAL_OUTPUT_SCAN_FAILED');
    exitCode = 1;
  }
}
