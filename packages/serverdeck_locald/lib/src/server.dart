import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';
import 'store.dart';

Future<void> protectDirectory(Directory directory) async {
  await directory.create(recursive: true);
  if (Platform.isWindows) {
    // Replace explicit grants too; protect existing files and refuse links.
    const script = r'''
$ErrorActionPreference = 'Stop'
$root = Get-Item -LiteralPath $env:SERVERDECK_PRIVATE_DIRECTORY -Force
function Protect-Item($item) {
  if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Reparse point refused' }
  $sid = [Security.Principal.WindowsIdentity]::GetCurrent().User
  if ($item.PSIsContainer) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
  } else {
    $acl = [Security.AccessControl.FileSecurity]::new()
    $inherit = [Security.AccessControl.InheritanceFlags]::None
  }
  $acl.SetAccessRuleProtection($true, $false)
  $acl.SetOwner($sid)
  foreach ($principal in @($sid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
    $rule = [Security.AccessControl.FileSystemAccessRule]::new($principal,
      [Security.AccessControl.FileSystemRights]::FullControl, $inherit,
      [Security.AccessControl.PropagationFlags]::None,
      [Security.AccessControl.AccessControlType]::Allow)
    $acl.AddAccessRule($rule)
  }
  $item.SetAccessControl($acl)
  if ($item.PSIsContainer) {
    foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) { Protect-Item $child }
  }
}
Protect-Item $root
''';
    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', script],
      environment: {'SERVERDECK_PRIVATE_DIRECTORY': directory.path},
    );
    if (result.exitCode != 0) {
      throw const LocalApiException('PrivateDirectoryUnavailable');
    }
  } else {
    final result = await Process.run('chmod', ['700', directory.path]);
    if (result.exitCode != 0) {
      throw const LocalApiException('PrivateDirectoryUnavailable');
    }
  }
}

final class LocaldServer {
  LocaldServer._(
    this.directory,
    this._lock,
    this._store,
    this._server,
    this.proof,
  );
  final Directory directory;
  final RandomAccessFile _lock;
  final LocalStore _store;
  final HttpServer _server;
  final String proof;
  late final StreamSubscription<HttpRequest> _requests;
  final Set<Future<void>> _pending = {};
  bool _closed = false;
  int get port => _server.port;

  static Future<LocaldServer> start({
    required String directory,
    required String nativeLibraryPath,
  }) async {
    final root = Directory(directory).absolute;
    await protectDirectory(root);
    final lock = await File('${root.path}/locald.lock')
        .open(mode: FileMode.append);
    try {
      await lock.lock(FileLock.exclusive);
    } catch (_) {
      await lock.close();
      throw const LocalApiException('ServiceAlreadyRunning');
    }
    LocalStore? store;
    HttpServer? server;
    try {
      store = await LocalStore.open(
        directory: '${root.path}/database',
        nativeLibraryPath: nativeLibraryPath,
      );
      server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: false,
      );
      final locald = LocaldServer._(root, lock, store, server, secureId());
      locald._requests = server.listen((request) {
        final future = locald._handle(request);
        locald._pending.add(future);
        unawaited(future.whenComplete(() => locald._pending.remove(future)));
      });
      final temporary = File('${root.path}/endpoint.tmp');
      await temporary.writeAsString(
        jsonEncode({
          'port': server.port,
          'proof': locald.proof,
          'apiVersion': localApiVersion,
          'pid': pid,
        }),
        flush: true,
      );
      final endpoint = File('${root.path}/endpoint.json');
      if (await endpoint.exists()) {
        await endpoint.delete();
      }
      await temporary.rename(endpoint.path);
      return locald;
    } catch (_) {
      await server?.close(force: true);
      await store?.close();
      await lock.unlock();
      await lock.close();
      rethrow;
    }
  }

  Future<void> _handle(HttpRequest request) async {
    var status = HttpStatus.ok;
    JsonMap result;
    try {
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
              'Bearer $proof' ||
          request.headers.value('origin') != null) {
        status = HttpStatus.unauthorized;
        throw const LocalApiException('Unauthenticated');
      }
      if (request.method != 'POST') {
        status = HttpStatus.methodNotAllowed;
        throw const LocalApiException('MethodNotAllowed');
      }
      final body = await _read(request).timeout(const Duration(seconds: 5));
      final data = switch (request.uri.path) {
        '/v1/health' => {
          'apiVersion': localApiVersion,
          'service': 'serverdeck',
        },
        '/v1/profiles/list' => await _store.profiles(),
        '/v1/profiles/initialize' => await _initialize(body),
        '/v1/profiles/save' => await _save(body),
        '/v1/profiles/remove' => await _remove(body),
        '/v1/jobs/list' => await _store.jobs(),
        '/v1/jobs/get' => await _store.getJob(body['id'] as String),
        '/v1/jobs/submit' => await _store.submit(
          JobPlan.fromJson(body['plan'] as JsonMap),
          body['idempotencyKey'] as String,
        ),
        '/v1/jobs/cancel' => await _cancel(body),
        '/v1/jobs/launch' => await _launch(body),
        '/v1/jobs/events' => await _store.events(
          body['id'] as String,
          after: body['after'] as int? ?? 0,
          limit: body['limit'] as int? ?? 100,
        ),
        _ => throw const LocalApiException('UnknownOperation'),
      };
      result = {'data': data};
    } on LocalApiException catch (e) {
      if (status == 200) {
        status = HttpStatus.badRequest;
      }
      result = {'error': e.code};
    } on FormatException {
      status = HttpStatus.badRequest;
      result = {'error': 'InvalidRequest'};
    } on TypeError {
      status = HttpStatus.badRequest;
      result = {'error': 'InvalidRequest'};
    } on TimeoutException {
      status = HttpStatus.requestTimeout;
      result = {'error': 'RequestTimeout'};
    } catch (_) {
      status = HttpStatus.internalServerError;
      result = {'error': 'ServiceFailure'};
    }
    try {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(jsonEncode(result));
      await request.response.close();
    } catch (_) {
      /* A disconnected observer cannot undo an accepted transaction. */
    }
  }

  Future<JsonMap> _read(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > 1024 * 1024) {
        throw const LocalApiException('RequestTooLarge');
      }
    }
    return jsonDecode(utf8.decode(bytes)) as JsonMap;
  }

  Future<bool> _initialize(JsonMap body) async {
    await _store.initializeProfiles((body['profiles'] as List).cast<JsonMap>());
    return true;
  }

  Future<bool> _save(JsonMap body) async {
    await _store.saveProfile(body['profile'] as JsonMap);
    return true;
  }

  Future<bool> _remove(JsonMap body) async {
    await _store.removeProfile(body['id'] as String);
    return true;
  }

  Future<bool> _cancel(JsonMap body) async {
    await _store.requestCancel(body['id'] as String);
    return true;
  }

  Future<bool> _launch(JsonMap body) async {
    await _store.approveAndLaunch(body['id'] as String);
    return true;
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _requests.cancel();
    await _server.close(force: true);
    await Future.wait(_pending.toList());
    await _store.close();
    final endpoint = File('${directory.path}/endpoint.json');
    if (await endpoint.exists()) {
      await endpoint.delete();
    }
    await _lock.unlock();
    await _lock.close();
  }
}
