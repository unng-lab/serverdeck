import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serverdeck/data/app_updates.dart';

class FakeTransport implements UpdateTransport {
  final responses = <String, UpdateResponse>{};
  int calls = 0;
  @override
  Future<UpdateResponse> get(Uri uri) async {
    calls++;
    return responses[uri.toString()] ??
        UpdateResponse(404, Stream.value(const []));
  }

  @override
  void close() {}
}

class DelayedTransport extends FakeTransport {
  final pending = Completer<UpdateResponse>();
  bool first = true;
  final delegate = source([1]);
  @override
  Future<UpdateResponse> get(Uri uri) {
    if (first) {
      first = false;
      return pending.future;
    }
    return delegate.get(uri);
  }
}

const packageUrl =
    'https://github.com/unng-lab/serverdeck/releases/download/v0.2.0+2/ServerDeck-0.2.0+2-windows-x64.msi';
const manifestUrl =
    'https://github.com/unng-lab/serverdeck/releases/download/v0.2.0+2/serverdeck-update.json';

Map<String, dynamic> manifest(List<int> bytes) => {
  'schemaVersion': 1,
  'version': '0.2.0+2',
  'notes': 'Обновлён интерфейс',
  'assets': {
    'windows-x64': {
      'url': packageUrl,
      'size': bytes.length,
      'sha256': sha256.convert(bytes).toString(),
    },
  },
};

FakeTransport source(List<int> bytes) {
  final fake = FakeTransport();
  UpdateResponse json(Object value) =>
      UpdateResponse(200, Stream.value(utf8.encode(jsonEncode(value))));
  fake.responses[latestReleaseUrl] = json({
    'tag_name': 'v0.2.0+2',
    'draft': false,
    'prerelease': false,
    'assets': [
      {'name': 'serverdeck-update.json', 'browser_download_url': manifestUrl},
    ],
  });
  fake.responses[manifestUrl] = json(manifest(bytes));
  fake.responses[packageUrl] = UpdateResponse(200, Stream.value(bytes));
  return fake;
}

void main() {
  test(
    'unresponsive check times out and a late result cannot replace retry',
    () async {
      final fake = DelayedTransport();
      final updater = AppUpdater(
        version: '0.1.0+1',
        platform: 'windows-x64',
        transport: fake,
      );
      final elapsed = Stopwatch()..start();
      await updater.check();
      expect(updater.state, UpdateState.error);
      expect(elapsed.elapsed, lessThan(const Duration(seconds: 30)));
      await updater.check();
      expect(updater.state, UpdateState.available);
      fake.pending.complete(UpdateResponse(404, Stream.value([])));
      await Future<void>.delayed(Duration.zero);
      expect(updater.state, UpdateState.available);
      updater.dispose();
    },
  );
  test('numeric version/build ordering and stable-only validation', () {
    expect(
      AppVersion.parse('1.10.0+1').compareTo(AppVersion.parse('1.9.9+99')),
      1,
    );
    expect(
      AppVersion.parse('1.0.0+2').compareTo(AppVersion.parse('1.0.0+1')),
      1,
    );
    for (final invalid in [
      'v1.0.0',
      '1.0',
      '1.0.0-beta',
      '01.0.0',
      '1.0.0+-1',
    ]) {
      expect(() => AppVersion.parse(invalid), throwsFormatException);
    }
  });

  test('manifest rejects foreign URLs, wrong types, traversal and size', () {
    for (final patch in [
      {'url': 'https://evil.invalid/a.exe'},
      {'url': packageUrl.replaceFirst('https:', 'http:')},
      {'url': packageUrl.replaceFirst('v0.2.0+2', 'v0.3.0+3')},
      {'url': packageUrl.replaceFirst('ServerDeck-', '../ServerDeck-')},
      {'size': 0},
      {'size': 1073741825},
      {'size': '123'},
      {'sha256': 'bad'},
    ]) {
      final value = manifest([1, 2, 3]);
      final asset = (value['assets'] as Map)['windows-x64'] as Map;
      asset.addAll(patch);
      expect(() => UpdateRelease.fromJson(value), throwsFormatException);
    }
  });

  test(
    'new release offered, same/older current, missing platform unsupported',
    () async {
      for (final (version, platform, expected) in [
        ('0.1.0+1', 'windows-x64', UpdateState.available),
        ('0.2.0+2', 'windows-x64', UpdateState.current),
        ('0.3.0+3', 'windows-x64', UpdateState.current),
        ('0.1.0+1', 'macos-arm64', UpdateState.unsupported),
      ]) {
        final updater = AppUpdater(
          version: version,
          platform: platform,
          transport: source([1]),
        );
        await updater.check();
        expect(updater.state, expected);
        updater.dispose();
      }
    },
  );

  test(
    '404 is unpublished; network failures and large metadata are errors',
    () async {
      final fake = FakeTransport();
      final updater = AppUpdater(
        version: '0.1.0+1',
        platform: 'windows-x64',
        transport: fake,
      );
      await updater.check();
      expect(updater.state, UpdateState.notPublished);
      fake.responses[latestReleaseUrl] = UpdateResponse(503, Stream.value([]));
      await updater.check();
      expect(updater.state, UpdateState.error);
      fake.responses[latestReleaseUrl] = UpdateResponse(
        200,
        Stream.value(List.filled(262145, 32)),
      );
      await updater.check();
      expect(updater.state, UpdateState.error);
      updater.dispose();
    },
  );

  test(
    'verified download opens only explicitly; tampering is refused',
    () async {
      final bytes = utf8.encode('fixture installer, never execute');
      var launches = 0;
      final updater = AppUpdater(
        version: '0.1.0+1',
        platform: 'windows-x64',
        transport: source(bytes),
        opener: (_) async {
          launches++;
        },
      );
      await updater.check();
      await updater.download();
      expect(updater.state, UpdateState.downloaded);
      expect(launches, 0);
      expect(await updater.downloadedFile!.readAsBytes(), bytes);
      await updater.openInstaller();
      expect(launches, 1);
      await updater.downloadedFile!.writeAsBytes([0]);
      await updater.openInstaller();
      expect(updater.state, UpdateState.error);
      expect(launches, 1);
      updater.dispose();
    },
  );

  test(
    'corruption/truncation/overflow refuse download and permit retry',
    () async {
      for (final corrupt in [
        [0, 0, 0],
        [1],
        [1, 2, 3, 4],
      ]) {
        final fake = source([1, 2, 3]);
        fake.responses[packageUrl] = UpdateResponse(200, Stream.value(corrupt));
        final updater = AppUpdater(
          version: '0.1.0+1',
          platform: 'windows-x64',
          transport: fake,
        );
        await updater.check();
        await updater.download();
        expect(updater.state, UpdateState.error);
        expect(updater.downloadedFile, isNull);
        fake.responses[packageUrl] = UpdateResponse(
          200,
          Stream.value([1, 2, 3]),
        );
        await updater.download();
        expect(updater.state, UpdateState.downloaded);
        updater.dispose();
      }
    },
  );

  test('check and download repeated clicks serialize', () async {
    final fake = source([1, 2, 3]);
    final updater = AppUpdater(
      version: '0.1.0+1',
      platform: 'windows-x64',
      transport: fake,
    );
    await Future.wait([updater.check(), updater.check()]);
    expect(fake.calls, 2);
    await Future.wait([updater.download(), updater.download()]);
    expect(fake.calls, 3);
    updater.dispose();
  });

  test('opener failure does not claim installed', () async {
    final updater = AppUpdater(
      version: '0.1.0+1',
      platform: 'windows-x64',
      transport: source([1]),
      opener: (_) async {
        throw const FileSystemException('fixture');
      },
    );
    await updater.check();
    await updater.download();
    await updater.openInstaller();
    expect(updater.state, UpdateState.error);
    updater.dispose();
  });
}
