import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/build_bundle.dart';
import 'package:serverdeck_windows/paths.dart';
import 'package:serverdeck_windows/process.dart';
import 'package:serverdeck_windows/security.dart';

import 'workspace_child.dart' as workspace;
import 'state_store_child.dart' as repository;
import 'state_store_crash_child.dart' as recovery;
import 'initialization_scenarios.dart' as initialization;
import 'secret_marker_scenarios.dart' as markers;

// Only this entrypoint reads these compile-time values. Normal locald does not
// import it, and neither CLI flags nor manifest edits can set this whitelist.
const fixtureRoot = String.fromEnvironment('SERVERDECK_TEST_FIXTURE_ROOT');
const ownerSid = String.fromEnvironment('SERVERDECK_TEST_OWNER_SID');
const modes = <String, String?>{
  'workspace-lifecycle': null,
  'repository': null,
  'credential-lifecycle': 'lifecycle',
  'mutations': 'mutations',
  'api': 'api',
  'channel': 'channel',
  'service-lifecycle': 'service-lifecycle',
  'resource-limits': 'mutation-limits',
};
const recoveryModes = <String, String>{
  'commit-before': 'before',
  'commit-after': 'after',
  'native-failure': 'failure',
  'dpapi-availability': 'dpapi',
  'verify-commit-before': 'verify-before',
  'verify-commit-after': 'verify-after',
  'verify-native-failure': 'verify-before',
  'verify-dpapi-availability': 'verify-after',
  'api-commit-before': 'api-before',
  'api-commit-after': 'api-after',
  'verify-api-commit-before': 'verify-api-before',
  'verify-api-commit-after': 'verify-api-after',
  'api-key-commit-before': 'api-key-before',
  'api-key-commit-after': 'api-key-after',
  'verify-api-key-commit-before': 'verify-api-key-before',
  'verify-api-key-commit-after': 'verify-api-key-after',
};

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 2 ||
        arguments[0] != '--scenario' ||
        (arguments[1] != 'secret-markers' &&
            arguments[1] != 'verify-secret-markers' &&
            arguments[1] != 'secret-markers-unsafe-acl' &&
            arguments[1] != 'verify-secret-markers-unsafe-acl' &&
            !modes.containsKey(arguments[1]) &&
            !recoveryModes.containsKey(arguments[1]) &&
            !initialization.initializationCases.containsKey(arguments[1]) &&
            !(arguments[1].startsWith('verify-') &&
                initialization.initializationCases.containsKey(
                  arguments[1].substring(7),
                ))) ||
        fixtureRoot.isEmpty ||
        ownerSid.isEmpty ||
        !p.isAbsolute(fixtureRoot) ||
        currentUserSid() != ownerSid) {
      throw StateError('TEST_BUILD_UNBOUND');
    }
    final root = p.normalize(fixtureRoot);
    if (!RegExp(r'^native-acceptance-[a-f0-9]{32}$')
        .hasMatch(p.basename(root))) {
      throw StateError('TEST_BUILD_UNBOUND');
    }
    requireSafePath(root, root);
    requireOwnerOnlyFileAcl(root, ownerSid);
    final testBundle = p.join(root, 'test-bundle');
    final normalBundle = p.join(root, 'normal-bundle');
    final manifest = await verifyBuildBundle(testBundle, testOnly: true);
    final identity = RetainedProcessIdentity.open(pid);
    try {
      verifyProcessImage(
        identity,
        ownerSid,
        p.join(testBundle, 'locald.exe'),
        manifest.sha256['locald.exe']!,
      );
    } finally {
      identity.close();
    }
    await verifyBuildBundle(normalBundle);
    // Each allowlisted case is single-use, including a failed partial run.
    // The protected CREATE_NEW claim also rejects concurrent attempts.
    final cases = p.join(root, 'cases');
    final scenario = arguments[1];
    final verifying = scenario.startsWith('verify-');
    final caseName = verifying ? scenario.substring(7) : scenario;
    final caseRoot = p.join(cases, caseName);
    final claim = p.join(root, '$scenario.claim');
    bool used() =>
        FileSystemEntity.typeSync(claim, followLinks: false) !=
            FileSystemEntityType.notFound ||
        (!verifying &&
            FileSystemEntity.typeSync(caseRoot, followLinks: false) !=
                FileSystemEntityType.notFound);
    if (used()) {
      throw StateError('TEST_FIXTURE_USED');
    }
    if (verifying &&
        (FileSystemEntity.typeSync(
                  p.join(root, '$caseName.claim'),
                  followLinks: false,
                ) !=
                FileSystemEntityType.file ||
            FileSystemEntity.typeSync(caseRoot, followLinks: false) !=
                FileSystemEntityType.directory)) {
      throw StateError('TEST_SCENARIO_FAILED');
    }
    try {
      await createProtectedEmptyFile(root, claim, ownerSid);
    } catch (_) {
      if (used()) throw StateError('TEST_FIXTURE_USED');
      rethrow;
    }
    createProtectedDirectory(root, cases, ownerSid);
    createProtectedDirectory(root, caseRoot, ownerSid);
    if (caseName == 'secret-markers' ||
        caseName == 'secret-markers-unsafe-acl') {
      await markers.run(caseRoot, normalBundle, verify: verifying);
    } else if (initialization.initializationCases.containsKey(caseName)) {
      await initialization.run(
        caseRoot,
        normalBundle,
        caseName,
        verify: verifying,
      );
    } else if (recoveryModes[scenario] case final String mode) {
      await recovery.main([caseRoot, normalBundle, mode]);
    } else if (scenario == 'workspace-lifecycle') {
      await workspace.main([caseRoot, normalBundle]);
    } else {
      await repository.main([
        caseRoot,
        normalBundle,
        if (modes[scenario] case final String mode) mode,
      ]);
    }
    stdout.writeln(
      'COMPILED_${scenario.toUpperCase().replaceAll('-', '_')}_PROVED',
    );
  } catch (error) {
    const safe = {
      'TEST_BUILD_UNBOUND',
      'TEST_FIXTURE_USED',
      'INIT_SCAN_PRIVATE_MARKER_FOUND',
      'INIT_SCAN_READ_OTHER',
    };
    stderr.writeln(
      error is StateError &&
              (safe.contains(error.message) ||
                  RegExp(r'^INIT_SCAN_READ_IO_-?\d+$')
                      .hasMatch('${error.message}'))
          ? error.message
          : 'TEST_SCENARIO_FAILED',
    );
    exitCode = 1;
  }
}
