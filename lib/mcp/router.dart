import 'dart:convert';
import 'dart:typed_data';

import '../console/console_models.dart';
import '../console/console_operations.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import 'grant_owner.dart';
import 'tool_schemas.dart';

final class McpRouter {
  McpRouter({
    required this.operations,
    required this.grants,
    required this.schemas,
    required this.release,
    this.consoles,
  });
  final AppOperations operations;
  final GrantOwner grants;
  final ToolSchemas schemas;
  final String release;
  final ConsoleOperations? consoles;
  McpSession session(McpActor actor) => McpSession._(this, actor);
}

final class _Request {
  bool cancelled = false;
}

final class McpSession {
  McpSession._(this.router, this.actor)
    : _consoleBinding = ConsoleMcpBinding(actor);
  final McpRouter router;
  final McpActor actor;
  final _seen = <Object>{}, _active = <Object, _Request>{};
  int _phase = 0;
  final ConsoleMcpBinding _consoleBinding;
  bool _closed = false;
  bool get closed => _closed;
  set closed(bool value) {
    if (!value || _closed) return;
    _closed = true;
    _consoleBinding.close();
    router.consoles?.disconnectBinding(_consoleBinding);
  }

  Object? _id(Object? value) {
    if (value is String && value.length <= 128) return ('s', value);
    if (value is num &&
        value.isFinite &&
        value.abs() <= 9007199254740991 &&
        value == value.truncateToDouble())
      return ('n', value.toInt());
    return null;
  }

  Map<String, Object?> _error(Object? id, int code, String message) => {
    'jsonrpc': '2.0',
    if (id != null) 'id': id,
    'error': {'code': code, 'message': message},
  };
  Map<String, Object?> _result(Object id, Object value) => {
    'jsonrpc': '2.0',
    'id': id,
    'result': value,
  };
  Future<Map<String, Object?>?> handle(Map<String, dynamic> frame) async {
    if (closed) return null;
    if (frame['jsonrpc'] != '2.0' ||
        frame['method'] is! String ||
        frame.keys.any(
          (k) => !['jsonrpc', 'id', 'method', 'params'].contains(k),
        ) ||
        (frame.containsKey('params') &&
            frame['params'] is! Map<String, dynamic>))
      return _error(null, -32600, 'INVALID_REQUEST');
    final method = frame['method'] as String,
        params = (frame['params'] as Map<String, dynamic>?) ?? {};
    if (!frame.containsKey('id')) {
      if (method == 'notifications/initialized' && _phase == 1) _phase = 2;
      if (method == 'notifications/cancelled') {
        final key = _id(params['requestId']);
        if (key != null) _active[key]?.cancelled = true;
      }
      return null;
    }
    final key = _id(frame['id']);
    if (key == null) return _error(null, -32600, 'INVALID_REQUEST');
    final id = frame['id'] as Object;
    if (!_seen.add(key)) return _error(id, -32600, 'INVALID_REQUEST');
    if (_seen.length > 10000) {
      closed = true;
      return _error(id, -32000, 'SESSION_LIMIT');
    }
    final request = _Request();
    _active[key] = request;
    final scoped = actor.cancellable(() => request.cancelled);
    try {
      await router.grants.authorize(scoped, AuthorizationPoint.admission);
      Object result;
      if (method == 'initialize') {
        if (_phase != 0 ||
            params['protocolVersion'] is! String ||
            params['capabilities'] is! Map ||
            params['clientInfo'] is! Map)
          return _error(id, -32602, 'INVALID_PARAMS');
        _phase = 1;
        result = {
          'protocolVersion': '2025-11-25',
          'serverInfo': {'name': 'ServerDeck', 'version': router.release},
          'capabilities': {
            'tools': {'listChanged': false},
          },
        };
      } else {
        if (_phase != 2) return _error(id, -32002, 'NOT_INITIALIZED');
        switch (method) {
          case 'ping':
            if (params.isNotEmpty) return _error(id, -32602, 'INVALID_PARAMS');
            result = <String, Object>{};
          case 'tools/list':
            if (params.isNotEmpty) return _error(id, -32602, 'INVALID_PARAMS');
            result = {'tools': router.schemas.tools};
          case 'tools/call':
            if (params.keys.any((k) => !['name', 'arguments'].contains(k)) ||
                params['name'] is! String ||
                params['arguments'] is! Map<String, dynamic>)
              return _error(id, -32602, 'INVALID_PARAMS');
            final name = params['name'] as String;
            if (!ToolSchemas.names.contains(name))
              return _error(id, -32602, 'UNKNOWN_TOOL');
            final arguments = router.schemas.arguments(
              name,
              params['arguments'] as Map<String, dynamic>,
            );
            var value = await _dispatch(scoped, name, arguments);
            if (utf8.encode(jsonEncode(value)).length > 1024 * 1024)
              value = {
                'ok': false,
                'error': const OperationFailure(FailureCode.resourceExhausted)
                    .toJson(),
              };
            router.schemas.output(name, value);
            result = {
              'content': [
                {'type': 'text', 'text': jsonEncode(value)},
              ],
              'structuredContent': value,
              'isError': value['ok'] != true,
            };
            if (utf8.encode(jsonEncode(_result(id, result))).length >
                1024 * 1024) {
              value = {
                'ok': false,
                'error': const OperationFailure(FailureCode.resourceExhausted)
                    .toJson(),
              };
              result = {
                'content': [
                  {'type': 'text', 'text': jsonEncode(value)},
                ],
                'structuredContent': value,
                'isError': true,
              };
            }
          default:
            return _error(id, -32601, 'METHOD_NOT_FOUND');
        }
      }
      if (request.cancelled) return _error(id, -32800, 'REQUEST_CANCELLED');
      await router.grants.authorize(scoped, AuthorizationPoint.response);
      return _result(id, result);
    } on SchemaFailure catch (e) {
      return _error(id, -32602, 'INVALID_PARAMS ${e.path}');
    } on OperationFailure {
      return _error(
        id,
        request.cancelled ? -32800 : -32001,
        request.cancelled ? 'REQUEST_CANCELLED' : 'ACCESS_DENIED',
      );
    } catch (_) {
      return _error(id, -32603, 'INTERNAL_ERROR');
    } finally {
      _active.remove(key);
    }
  }

  AuthenticationInput _auth(Map<String, dynamic> a) {
    if (a['kind'] == 'password') return PasswordInput(a['password'] as String);
    final encoded = a['keyBase64'] as String;
    Uint8List bytes;
    try {
      bytes = base64.decode(encoded);
    } on FormatException {
      throw const SchemaFailure(r'$.authentication.keyBase64');
    }
    if (bytes.isEmpty ||
        bytes.length > 1024 * 1024 ||
        base64.encode(bytes) != encoded)
      throw const SchemaFailure(r'$.authentication.keyBase64');
    try {
      return PrivateKeyInput(bytes, passphrase: a['passphrase'] as String?);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  TrustDecision _decision(Map<String, dynamic> a) => TrustDecision(
    profileId: a['profileId'] as String,
    attemptId: a['attemptId'] as String,
    nonce: a['nonce'] as String,
    expectedProfileRevision: a['expectedProfileRevision'] as int,
    expectedTrustRevision: a['expectedTrustRevision'] as int,
    expectedObservationRevision: a['expectedObservationRevision'] as int,
    fingerprint: a['fingerprint'] as String,
    mutationId: a['mutationId'] as String,
    confirmed: a['confirmed'] as bool,
  );
  Future<Map<String, Object?>> _dispatch(
    McpActor actor,
    String name,
    Map<String, dynamic> a,
  ) async {
    final op = router.operations;
    final p = a['profileId'] as String?;
    if (name.startsWith('console.')) return _consoleDispatch(actor, name, a);
    switch (name) {
      case 'profiles.list':
        return (await op.listProfiles(
          actor,
          limit: a['limit'] as int? ?? 50,
          cursor: a['cursor'] as String?,
        )).toJson();
      case 'profiles.get':
        return (await op.getProfile(actor, p!)).toJson();
      case 'profiles.create':
        final data = a['profile'] as Map<String, dynamic>,
            auth = _auth(data['authentication'] as Map<String, dynamic>);
        try {
          return (await op.createProfile(
            actor,
            ProfileDraft(
              displayName: data['displayName'] as String,
              host: data['host'] as String,
              port: data['port'] as int?,
              username: data['username'] as String,
              authentication: auth,
            ),
            mutationId: a['mutationId'] as String,
          )).toJson();
        } finally {
          auth.dispose();
        }
      case 'profiles.update':
        final patch = a['patch'] as Map<String, dynamic>,
            auth = patch['authentication'] == null
                ? null
                : _auth(patch['authentication'] as Map<String, dynamic>);
        try {
          return (await op.updateProfile(
            actor,
            p!,
            ProfilePatch(
              displayName: patch['displayName'] as String?,
              host: patch['host'] as String?,
              port: patch['port'] as int?,
              username: patch['username'] as String?,
              authentication: auth,
            ),
            expectedRevision: a['expectedRevision'] as int,
            mutationId: a['mutationId'] as String,
          )).toJson();
        } finally {
          auth?.dispose();
        }
      case 'connections.connect':
        return (await op.connect(
          actor,
          p!,
          expectedRevision: a['expectedRevision'] as int,
        )).toJson();
      case 'connections.get':
        return (await op.getConnection(actor, p!)).toJson();
      case 'connections.provide_passphrase':
        return (await op.providePassphrase(
          actor,
          p!,
          attemptId: a['attemptId'] as String,
          nonce: a['nonce'] as String,
          passphrase: a['passphrase'] as String,
        )).toJson();
      case 'connections.cancel':
        return (await op.cancelConnection(
          actor,
          p!,
          attemptId: a['attemptId'] as String,
        )).toJson();
      case 'connections.disconnect':
        return (await op.disconnect(
          actor,
          p!,
          sessionId: a['sessionId'] as String,
        )).toJson();
      case 'trust.get':
        return (await op.getTrust(actor, p!)).toJson();
      case 'trust.accept':
        return (await op.acceptTrust(actor, _decision(a))).toJson();
      case 'trust.replace':
        return (await op.replaceTrust(
          actor,
          ReplacementDecision(
            profileId: p!,
            attemptId: a['attemptId'] as String,
            nonce: a['nonce'] as String,
            expectedProfileRevision: a['expectedProfileRevision'] as int,
            expectedTrustRevision: a['expectedTrustRevision'] as int,
            expectedObservationRevision:
                a['expectedObservationRevision'] as int,
            fingerprint: a['newFingerprint'] as String,
            oldFingerprint: a['oldFingerprint'] as String,
            newFingerprint: a['newFingerprint'] as String,
            mutationId: a['mutationId'] as String,
            confirmed: a['confirmed'] as bool,
          ),
        )).toJson();
      case 'trust.retain':
        return (await op.retainTrust(
          actor,
          RetentionDecision(
            profileId: p!,
            attemptId: a['attemptId'] as String,
            nonce: a['nonce'] as String,
            expectedProfileRevision: a['expectedProfileRevision'] as int,
            expectedTrustRevision: a['expectedTrustRevision'] as int,
            expectedObservationRevision:
                a['expectedObservationRevision'] as int,
            fingerprint: a['acceptedFingerprint'] as String,
            acceptedFingerprint: a['acceptedFingerprint'] as String,
            mutationId: a['mutationId'] as String,
            confirmed: a['confirmed'] as bool,
          ),
        )).toJson();
      default:
        throw const SchemaFailure(r'$.name');
    }
  }

  Future<Map<String, Object?>> _consoleDispatch(
    McpActor actor,
    String name,
    Map<String, dynamic> a,
  ) async {
    final op = router.consoles;
    if (op == null)
      return const OperationResult<ConsoleValue>.failure(
        OperationFailure(FailureCode.consoleInactive),
      ).toJson();
    final caller = ConsoleCaller.mcp(actor, _consoleBinding);
    final profile = a['profileId'] as String?,
        session = a['sessionId'] as String?;
    final generation = a['generation'] as int?;
    final epoch = a['ownerEpoch'] as String?;
    final sequence = a['operationSequence'] as int?;
    final result = switch (name) {
      'console.profiles' => await op.consoleProfiles(caller),
      'console.list' => await op.listConsoles(caller, profile!),
      'console.open' => await op.openConsole(
        caller,
        profile!,
        shellProfileId: a['shellProfileId'] as String?,
        ownerEpoch: epoch,
        operationSequence: sequence,
      ),
      'console.read' => await op.readConsole(
        caller,
        profile!,
        session!,
        generation: generation!,
        cursor: a['cursor'] as String?,
        limit: a['limit'] as int? ?? 1000,
      ),
      'console.acquire' => await op.acquireConsole(
        caller,
        profile!,
        session!,
        generation: generation!,
        ownerEpoch: epoch,
        operationSequence: sequence,
      ),
      'console.release' => await op.releaseConsole(
        caller,
        profile!,
        session!,
        generation: generation!,
        leaseToken: a['leaseToken'] as String,
        ownerEpoch: epoch,
        operationSequence: sequence,
      ),
      'console.write' => await op.writeConsole(
        caller,
        profile!,
        session!,
        generation: generation!,
        leaseToken: a['leaseToken'] as String,
        text: a['text'] as String?,
        key: a['key'] as String?,
        confirmedMultiline: a['confirmedMultiline'] as bool? ?? false,
        ownerEpoch: epoch,
        operationSequence: sequence,
      ),
      'console.close' => await op.closeConsole(
        caller,
        profile!,
        session!,
        generation: generation!,
        leaseToken: a['leaseToken'] as String?,
        confirmed: a['confirmed'] as bool? ?? false,
        ownerEpoch: epoch,
        operationSequence: sequence,
      ),
      _ => throw const SchemaFailure(r'$.name'),
    };
    return result.toJson();
  }
}
