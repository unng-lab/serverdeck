import 'dart:convert';
import 'dart:io';

import 'package:serverdeck/storage/migrations.dart';
import 'package:serverdeck/storage/records.dart';
import 'package:serverdeck/storage/workspace_store.dart';

final _uuid = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Map<String, Object> values(AppSettings settings) => {
  'id': settings.id,
  'logicalFormat': settings.logicalFormat,
  'settingsRevision': settings.settingsRevision,
  'dataRevision': settings.dataRevision,
  'profilesListRevision': settings.profilesListRevision,
  'theme': settings.theme,
  'mcpEnabled': settings.mcpEnabled,
  'createdAt': settings.createdAt,
};

void require(bool condition, String code) {
  if (!condition) throw StateError(code);
}

void respond(Map<String, Object> value) {
  stdout.writeln('SERVERDECK_DURABILITY_V1 ${jsonEncode(value)}');
}

void assertValues(Map<String, Object> actual, bool committed, int createdAt) {
  require(
    actual['id'] == 1 &&
        actual['logicalFormat'] == 1 &&
        actual['settingsRevision'] == (committed ? 2 : 1) &&
        actual['dataRevision'] == (committed ? 2 : 1) &&
        actual['profilesListRevision'] == 1 &&
        actual['theme'] == (committed ? 'light' : 'dark') &&
        actual['mcpEnabled'] == false &&
        actual['createdAt'] == createdAt,
    'PARTIAL_OR_UNEXPECTED_RECORD',
  );
}

Future<void> main(List<String> args) async {
  try {
    require(Platform.isWindows && args.length == 4, 'INVALID_ARGUMENTS');
    final mode = args[0];
    require(
      {
        'init',
        'write-committed',
        'write-uncommitted',
        'verify-old',
        'verify-new',
      }.contains(mode),
      'INVALID_MODE',
    );
    final root = Directory(args[1]);
    final library = File(args[2]);
    final nonce = args[3];
    final leaf = root.absolute.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;
    require(
      root.isAbsolute &&
          leaf.startsWith('ServerDeckDurability-') &&
          _uuid.hasMatch(leaf.substring('ServerDeckDurability-'.length)) &&
          _uuid.hasMatch(nonce) &&
          library.isAbsolute &&
          library.existsSync(),
      'INVALID_FIXTURE_PATH_OR_NONCE',
    );
    await rejectLinks(root.path);
    await rejectLinks(library.path);
    require(root.existsSync(), 'FIXTURE_ROOT_MISSING');
    final marker = File('${root.path}/fixture.json');
    final phase = File('${root.path}/phase.json');
    int? createdAt;
    if (mode == 'init') {
      require(root.listSync().isEmpty, 'FIXTURE_INIT_REQUIRES_EMPTY_ROOT');
      marker.writeAsStringSync(
        jsonEncode({'schemaVersion': 1, 'nonce': nonce, 'ready': false}),
        flush: true,
      );
    } else {
      await rejectLinks(marker.path);
      require(
        marker.existsSync() && marker.lengthSync() <= 4096,
        'FIXTURE_MARKER_MISSING',
      );
      final identity =
          jsonDecode(marker.readAsStringSync()) as Map<String, dynamic>;
      require(
        identity['schemaVersion'] == 1 &&
            identity['nonce'] == nonce &&
            identity['ready'] == true &&
            identity['createdAt'] is int,
        'FIXTURE_IDENTITY_MISMATCH',
      );
      createdAt = identity['createdAt'] as int;
      if (mode.startsWith('write-')) {
        require(!phase.existsSync(), 'FIXTURE_PHASE_ALREADY_EXISTS');
      } else {
        await rejectLinks(phase.path);
        require(
          phase.existsSync() && phase.lengthSync() <= 4096,
          'FIXTURE_PHASE_MISSING',
        );
        final barrier =
            jsonDecode(phase.readAsStringSync()) as Map<String, dynamic>;
        require(
          barrier['schemaVersion'] == 1 &&
              barrier['nonce'] == nonce &&
              barrier['phase'] ==
                  (mode == 'verify-new' ? 'committed' : 'inside-transaction'),
          'FIXTURE_PHASE_MISMATCH',
        );
      }
    }
    final store = WorkspaceStore(
      dataRoot: root.path,
      libraryPath: library.path,
      // Synthetic first-publication setup, not a test of native publication.
      // Only init may invoke it, and init has just claimed an empty scratch root.
      flushAtomic: (path, bytes) async {
        require(
          mode == 'init' && path.startsWith('data/publish/'),
          'UNEXPECTED_PUBLICATION',
        );
        final id = path.substring('data/publish/'.length);
        require(_uuid.hasMatch(id), 'INVALID_PUBLICATION_ID');
        await Directory('${root.path}/data/stores').create(recursive: true);
        await Directory('${root.path}/data/staging-$id')
            .rename('${root.path}/data/stores/$id');
        await File('${root.path}/data/CURRENT.json')
            .writeAsBytes(bytes, flush: true);
      },
    );
    await store.open();
    final before = await store.write(
      (db) => values(db.appSettings.getSync(1)!),
    );
    if (mode == 'init') {
      createdAt = before['createdAt']! as int;
      assertValues(before, false, createdAt);
      await store.close();
      marker.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'nonce': nonce,
          'ready': true,
          'createdAt': createdAt,
        }),
        flush: true,
      );
      respond({'status': 'initialized', 'values': before});
      return;
    }
    if (mode.startsWith('verify-')) {
      assertValues(before, mode == 'verify-new', createdAt!);
      await store.close();
      respond({'status': mode, 'values': before});
      return;
    }
    assertValues(before, false, createdAt!);
    void signal(String name) {
      phase.writeAsStringSync(
        jsonEncode({
          'schemaVersion': 1,
          'nonce': nonce,
          'writerPid': pid,
          'phase': name,
        }),
        flush: true,
      );
    }

    await store.write<void>((db) {
      final settings = db.appSettings.getSync(1)!
        ..theme = 'light'
        ..settingsRevision = 2
        ..dataRevision = 2;
      db.appSettings.putSync(settings);
      if (mode == 'write-uncommitted') {
        // Deliberate fault barrier, not ordinary production transaction work.
        // Sync file flush makes the crash point observable without an SDK/debugger.
        signal('inside-transaction');
        sleep(const Duration(seconds: 60));
        throw StateError('WRITER_WAS_NOT_TERMINATED');
      }
    });
    signal('committed'); // Only after the real WorkspaceStore lease committed.
    sleep(const Duration(seconds: 60));
    throw StateError('WRITER_WAS_NOT_TERMINATED');
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
