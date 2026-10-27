import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:serverdeck_windows/mcp_credential_file_probe.dart';

import '../mcp_credential_files_test.dart' as fixture;

Future<void> denied(Future<void> operation, String code) async {
  try {
    await operation;
  } on StateError catch (e) {
    if (e.message == code) return;
    throw StateError('WRONG_SPACE_FAILURE_CODE');
  }
  throw StateError('EXPECTED_SPACE_REFUSAL');
}

Future<void> main(List<String> args) async {
  if (args.single == 'disabled') {
    if (mcpCredentialFileProbesEnabled)
      throw StateError('UNEXPECTED_PROBE_BUILD');
    var refused = 0;
    try {
      McpCredentialFileProbe.installMinimumBytes(0x7fffffffffffffff);
    } on StateError catch (e) {
      if (e.message == 'MCP_FILE_PROBE_UNAVAILABLE') refused++;
    }
    try {
      McpCredentialFileProbe.minimumBytes(128 * 1024);
    } on StateError catch (e) {
      if (e.message == 'MCP_FILE_PROBE_UNAVAILABLE') refused++;
    }
    if (refused != 2) throw StateError('ORDINARY_BUILD_PROBE_ACCESS');
    stdout.writeln('PROBES_DISABLED');
    return;
  }
  if (!mcpCredentialFileProbesEnabled) throw StateError('MISSING_PROBE_BUILD');
  final f = fixture.Fixture();
  try {
    final mode = args.single;
    if (mode != 'initial') {
      await f.files.stage(f.binding());
      await f.files.publish(f.binding(), revoked: false);
    }
    if (mode == 'publish') await f.files.stage(f.binding(fixture.replacement));
    final before = mode == 'initial' ? null : File(f.lookup).readAsBytesSync();
    McpCredentialFileProbe.installMinimumBytes(0x7fffffffffffffff);
    if (mode == 'initial' || mode == 'stage') {
      await denied(
        f.files.stage(f.binding(fixture.replacement)),
        'RESOURCE_LIMIT',
      );
      if (mode == 'initial' && Directory(f.credentials).existsSync())
        throw StateError('CREATED_BEFORE_SPACE_GATE');
      if (File(
        p.join(f.credentials, fixture.grant, '${fixture.replacement}.dpapi'),
      ).existsSync()) {
        throw StateError('CANDIDATE_WRITTEN_ON_SPACE_REFUSAL');
      }
    } else if (mode == 'publish' || mode == 'revoke') {
      await denied(
        f.files.publish(
          mode == 'publish' ? f.binding(fixture.replacement) : f.binding(),
          revoked: mode == 'revoke',
        ),
        'STORAGE_BLOCKED',
      );
    } else {
      throw StateError('UNKNOWN_MODE');
    }
    if (before != null) {
      final actual = File(f.lookup).readAsBytesSync();
      if (before.length != actual.length) throw StateError('LOOKUP_CHANGED');
      for (var n = 0; n < before.length; n++) {
        if (before[n] != actual[n]) throw StateError('LOOKUP_CHANGED');
      }
      // A correct current pointer never needs a write or the failing space gate.
      await f.files.publish(f.binding(), revoked: false);
      final existing = await f.files.readForBridge(fixture.grant);
      existing.key.close();
    }
    stdout.writeln('SPACE_REFUSED');
  } finally {
    f.close();
  }
}
