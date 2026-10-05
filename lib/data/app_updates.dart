import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

const latestReleaseUrl =
    'https://api.github.com/repos/unng-lab/serverdeck/releases/latest';
const maxPackageSize = 1024 * 1024 * 1024;

class AppVersion implements Comparable<AppVersion> {
  AppVersion._(this.value, this.parts);
  final String value;
  final List<int> parts;
  factory AppVersion.parse(String value) {
    if (!RegExp(
          r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:\+(0|[1-9]\d*))?$',
        ).hasMatch(value) ||
        value.length > 64) {
      throw const FormatException('Invalid stable version');
    }
    final parts = value.split(RegExp(r'[.+]')).map(int.parse).toList();
    if (parts.length == 3) parts.add(0);
    return AppVersion._(value, parts);
  }
  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < parts.length; i++) {
      final c = parts[i].compareTo(other.parts[i]);
      if (c != 0) return c;
    }
    return 0;
  }
}

bool trustedReleaseUri(Uri uri, {String? tag}) {
  final segments = uri.pathSegments;
  return uri.scheme == 'https' &&
      uri.host == 'github.com' &&
      !uri.hasPort &&
      uri.userInfo.isEmpty &&
      !uri.hasQuery &&
      !uri.hasFragment &&
      segments.length == 6 &&
      segments[0] == 'unng-lab' &&
      segments[1] == 'serverdeck' &&
      segments[2] == 'releases' &&
      segments[3] == 'download' &&
      (tag == null || segments[4] == tag) &&
      RegExp(r'^[A-Za-z0-9_.+-]+$').hasMatch(segments.last) &&
      segments.last != '.' &&
      segments.last != '..';
}

class UpdateAsset {
  UpdateAsset(this.uri, this.size, this.digest);
  final Uri uri;
  final int size;
  final String digest;
  String get filename => uri.pathSegments.last;
  factory UpdateAsset.fromJson(
    Map<String, dynamic> json,
    String key,
    String tag,
  ) {
    final url = json['url'], size = json['size'], digest = json['sha256'];
    final suffix = switch (key) {
      'windows-x64' => '.msi',
      'macos-x64' || 'macos-arm64' => '.dmg',
      'linux-x64' => '.deb',
      _ => throw const FormatException('Unsupported asset'),
    };
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        !trustedReleaseUri(uri, tag: tag) ||
        !uri.path.endsWith(suffix) ||
        size is! int ||
        size < 1 ||
        size > maxPackageSize ||
        digest is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const FormatException('Invalid asset');
    }
    return UpdateAsset(uri, size, digest);
  }
}

class UpdateRelease {
  UpdateRelease(this.version, this.notes, this.assets);
  final AppVersion version;
  final String notes;
  final Map<String, UpdateAsset> assets;
  factory UpdateRelease.fromJson(Map<String, dynamic> json) {
    final version = json['version'],
        notes = json['notes'],
        assets = json['assets'];
    if (json['schemaVersion'] != 1 ||
        version is! String ||
        notes is! String ||
        notes.length > 20000 ||
        assets is! Map<String, dynamic> ||
        assets.isEmpty ||
        assets.length > 4) {
      throw const FormatException('Invalid manifest');
    }
    final parsed = AppVersion.parse(version);
    final packages = <String, UpdateAsset>{};
    for (final entry in assets.entries) {
      if (entry.value is! Map<String, dynamic>) {
        throw const FormatException('Invalid asset');
      }
      packages[entry.key] = UpdateAsset.fromJson(
        entry.value,
        entry.key,
        'v$version',
      );
    }
    return UpdateRelease(parsed, notes, packages);
  }
}

class UpdateResponse {
  UpdateResponse(this.status, this.bytes);
  final int status;
  final Stream<List<int>> bytes;
}

abstract interface class UpdateTransport {
  Future<UpdateResponse> get(Uri uri);
  void close();
}

class GitHubUpdateTransport implements UpdateTransport {
  HttpClient? _client;
  @override
  Future<UpdateResponse> get(Uri uri) async {
    if (uri.toString() != latestReleaseUrl && !trustedReleaseUri(uri)) {
      throw const FormatException('Untrusted source');
    }
    final client = _client ??= HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    for (var hop = 0; hop <= 5; hop++) {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 20));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'ServerDeck');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (![301, 302, 303, 307, 308].contains(response.statusCode)) {
        return UpdateResponse(response.statusCode, response);
      }
      final location = response.headers.value(HttpHeaders.locationHeader);
      // Cancel the redirect body without trusting its length.
      await response.listen((_) {}).cancel();
      if (location == null) throw const FormatException('Invalid redirect');
      final next = uri.resolve(location);
      final cdn =
          next.scheme == 'https' &&
          !next.hasPort &&
          next.userInfo.isEmpty &&
          {
            'release-assets.githubusercontent.com',
            'objects.githubusercontent.com',
          }.contains(next.host);
      if (!trustedReleaseUri(next) && !cdn) {
        throw const FormatException('Untrusted redirect');
      }
      uri = next;
    }
    throw const FormatException('Too many redirects');
  }

  @override
  void close() {
    _client?.close(force: true);
    _client = null;
  }
}

enum UpdateState {
  idle,
  checking,
  current,
  available,
  notPublished,
  unsupported,
  downloading,
  downloaded,
  error,
}

abstract class UpdateController extends ChangeNotifier {
  UpdateState get state;
  String get installedVersion;
  String? get availableVersion;
  String get notes;
  String get message;
  double? get progress;
  bool get isStore => false;
  bool get busy =>
      state == UpdateState.checking || state == UpdateState.downloading;
  Future<void> check();
  Future<void> download();
  Future<void> openInstaller();
  Future<void> openStore() async {}
}

String desktopPlatformKey() => switch (Abi.current()) {
  Abi.windowsX64 => 'windows-x64',
  Abi.macosX64 => 'macos-x64',
  Abi.macosArm64 => 'macos-arm64',
  Abi.linuxX64 => 'linux-x64',
  _ => 'unsupported',
};

class AppUpdater extends UpdateController {
  AppUpdater({
    required String version,
    required this.platform,
    UpdateTransport? transport,
    Future<void> Function(File)? opener,
  }) : currentVersion = AppVersion.parse(version),
       _transport = transport ?? GitHubUpdateTransport(),
       _opener = opener ?? openPackage;
  final AppVersion currentVersion;
  final String platform;
  final UpdateTransport _transport;
  final Future<void> Function(File) _opener;
  UpdateRelease? release;
  File? downloadedFile;
  Directory? _temporary;
  bool _disposed = false, _opening = false;
  int _checkGeneration = 0;
  int _bytes = 0;
  @override
  UpdateState state = UpdateState.idle;
  @override
  String message = '';
  @override
  String get installedVersion => currentVersion.value;
  @override
  String? get availableVersion => release?.version.value;
  @override
  String get notes => release?.notes ?? '';
  UpdateAsset? get asset => release?.assets[platform];
  @override
  double? get progress => asset == null ? null : _bytes / asset!.size;
  void _emit(UpdateState next, [String text = '']) {
    if (_disposed) return;
    state = next;
    message = text;
    notifyListeners();
  }

  Future<Map<String, dynamic>?> _json(Uri uri, {bool allow404 = false}) async {
    final response = await _transport.get(uri);
    if (allow404 && response.status == 404) {
      await response.bytes.listen((_) {}).cancel();
      return null;
    }
    if (response.status != 200) {
      await response.bytes.listen((_) {}).cancel();
      throw const HttpException('Release source unavailable');
    }
    final bytes = <int>[];
    await for (final chunk in response.bytes.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > 256 * 1024) {
        throw const FormatException('Metadata too large');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid metadata');
    }
    return decoded;
  }

  @override
  Future<void> check() async {
    if (busy || _opening || _disposed) return;
    final generation = ++_checkGeneration;
    _emit(UpdateState.checking);
    try {
      await (() async {
        final latest = await _json(Uri.parse(latestReleaseUrl), allow404: true);
        if (_disposed || generation != _checkGeneration) return;
        if (latest == null) {
          release = null;
          _emit(UpdateState.notPublished);
          return;
        }
        if (latest['draft'] != false ||
            latest['prerelease'] != false ||
            latest['assets'] is! List ||
            latest['tag_name'] is! String) {
          throw const FormatException('Invalid stable release');
        }
        final candidates = (latest['assets'] as List)
            .where((a) => a is Map && a['name'] == 'serverdeck-update.json')
            .toList();
        if (candidates.length != 1 ||
            candidates.single['browser_download_url'] is! String) {
          throw const FormatException('Manifest missing');
        }
        final uri = Uri.parse(candidates.single['browser_download_url']);
        if (!trustedReleaseUri(uri, tag: latest['tag_name'])) {
          throw const FormatException('Untrusted manifest');
        }
        final parsed = UpdateRelease.fromJson((await _json(uri))!);
        if (latest['tag_name'] != 'v${parsed.version.value}') {
          throw const FormatException('Release version mismatch');
        }
        if (_disposed || generation != _checkGeneration) return;
        release = parsed;
        _emit(
          parsed.version.compareTo(currentVersion) <= 0
              ? UpdateState.current
              : asset == null
              ? UpdateState.unsupported
              : UpdateState.available,
        );
      })().timeout(const Duration(seconds: 25));
    } catch (_) {
      if (_disposed || generation != _checkGeneration) return;
      _checkGeneration++;
      _transport.close();
      _emit(
        UpdateState.error,
        'Не удалось проверить обновления. Проверьте сеть и повторите.',
      );
    }
  }

  Future<void> _clean() async {
    downloadedFile = null;
    final temporary = _temporary;
    _temporary = null;
    if (temporary != null && await temporary.exists()) {
      // Only the unique directory created by this updater is ever removed.
      await temporary.delete(recursive: true);
    }
  }

  @override
  Future<void> download() async {
    if (busy ||
        _opening ||
        _disposed ||
        asset == null ||
        release!.version.compareTo(currentVersion) <= 0) {
      return;
    }
    _bytes = 0;
    _emit(UpdateState.downloading);
    try {
      await _clean();
      final temporary = await Directory.systemTemp.createTemp(
        'serverdeck-update-',
      );
      _temporary = temporary;
      if (!Platform.isWindows) {
        final protection = await Process.run('chmod', ['700', temporary.path]);
        if (protection.exitCode != 0) {
          throw const FileSystemException('Private download unavailable');
        }
      }
      final file = File(p.join(temporary.path, '${asset!.filename}.part'));
      final output = await file.open(mode: FileMode.write);
      try {
        await (() async {
          final response = await _transport.get(asset!.uri);
          if (response.status != 200) {
            await response.bytes.listen((_) {}).cancel();
            throw const HttpException('Download unavailable');
          }
          await for (final chunk in response.bytes.timeout(
            const Duration(seconds: 30),
          )) {
            if (_disposed || state != UpdateState.downloading) {
              throw const HttpException('Download cancelled');
            }
            _bytes += chunk.length;
            if (_bytes > asset!.size) {
              throw const FormatException('Package too large');
            }
            await output.writeFrom(chunk);
            notifyListeners();
          }
        })().timeout(const Duration(minutes: 30));
      } finally {
        await output.close();
      }
      await _verify(file);
      if (_disposed || state != UpdateState.downloading) {
        throw const HttpException('Download cancelled');
      }
      downloadedFile = await file.rename(
        p.join(temporary.path, asset!.filename),
      );
      _emit(UpdateState.downloaded);
    } catch (_) {
      _transport.close();
      await _clean();
      _emit(
        UpdateState.error,
        'Загрузка или проверка файла не удалась. Повторите загрузку.',
      );
    }
  }

  Future<void> _verify(File file) async {
    if (await file.length() != asset!.size ||
        (await sha256.bind(file.openRead()).first).toString() !=
            asset!.digest) {
      throw const FormatException('Package integrity mismatch');
    }
  }

  @override
  Future<void> openInstaller() async {
    if (busy || _opening || _disposed || downloadedFile == null) return;
    _opening = true;
    try {
      await _verify(downloadedFile!);
      await _opener(downloadedFile!);
      _emit(
        UpdateState.downloaded,
        'Установщик открыт. Завершите обновление и запустите ServerDeck заново.',
      );
    } catch (_) {
      _emit(
        UpdateState.error,
        'Не удалось открыть проверенный установщик. Повторите загрузку.',
      );
    } finally {
      _opening = false;
    }
  }

  static Future<void> openPackage(File file) async {
    if (Platform.isWindows) {
      await Process.start('msiexec.exe', [
        '/i',
        file.path,
      ], mode: ProcessStartMode.detached);
    } else {
      final result = await Process.run(Platform.isMacOS ? 'open' : 'xdg-open', [
        file.path,
      ]).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) {
        throw const FileSystemException('Installer opener unavailable');
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _transport.close();
    // Files remain available while an installer is using them; unique OS temp
    // directories can be cleaned by the OS. Partial active downloads clean up.
    super.dispose();
  }
}
