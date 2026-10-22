import 'dart:async';
import 'dart:convert';

import 'package:cryptography/dart.dart';
import 'package:serverdeck_protocol/automation/models.dart';
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/mcp/catalog.dart';
import 'package:serverdeck_protocol/mcp/handshake.dart';
import 'package:serverdeck_protocol/mcp/operations.dart';
import 'package:serverdeck_protocol/mcp/wire.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../api/operational_auth.dart';
import '../api/owner_service_probe.dart';
import '../storage/key_custody.dart';
import '../storage/state_store.dart';
import 'profile_commands.dart';
import 'profile_diff.dart';
import 'snapshot.dart';

const profileCatalogOperations = {
  'list',
  'get',
  'create',
  'update',
  'compare',
  'validate',
  'archive',
};

/// Immutable normalized request. Neither this value nor a command grants access.
final class ProfileCatalogInput {
  ProfileCatalogInput._(
    this.operation,
    this._json,
    this.command,
    this.body, [
    this._parsed = true,
    this._parseElapsed = Duration.zero,
  ]);
  factory ProfileCatalogInput.capture(
    String operation,
    Map<String, Object?> params,
  ) {
    if (!profileCatalogOperations.contains(operation))
      throw StateError('UNSUPPORTED');
    try {
      return ProfileCatalogInput._(
        operation,
        utf8.decode(encodeMcpMessage(params, maxBytes: 256 * 1024)),
        null,
        null,
        false,
      );
    } on McpProtocolException {
      throw const FormatException('VALIDATION');
    }
  }
  factory ProfileCatalogInput.parse(
    String operation,
    Map<String, Object?> params,
  ) {
    final parsing = Stopwatch()..start();
    if (!profileCatalogOperations.contains(operation))
      throw StateError('UNSUPPORTED');
    validateMcpArguments(mcpTool('serverdeck_profiles_$operation')!, params);
    final json = utf8.decode(
      StrictCodec().encode(params, maxBytes: 256 * 1024),
    );
    final mutation = {'create', 'update', 'archive'}.contains(operation);
    final command = mutation
        ? AutomationProfileCommand.parse('profile.$operation', params)
        : null;
    AutomationBody? body;
    if (operation == 'validate') {
      try {
        body = AutomationBody.fromJson(params['body'] as Map<String, Object?>);
      } on FormatException {
        body = null;
      }
    }
    return ProfileCatalogInput._(
      operation,
      json,
      command,
      body,
      true,
      parsing.elapsed,
    );
  }
  final String operation, _json;
  final AutomationProfileCommand? command;
  final AutomationBody? body;
  final bool _parsed;
  final Duration _parseElapsed;
  ProfileCatalogInput _resolve() =>
      _parsed ? this : ProfileCatalogInput.parse(operation, params);
  Map<String, Object?> get params => jsonDecode(_json) as Map<String, Object?>;
  bool get mutation => {'create', 'update', 'archive'}.contains(operation);
}

/// No public constructor or caller-selected origin/role. Bound to one service.
final class ProfileCatalogActor {
  ProfileCatalogActor._(this._service, this._operation, this._owner, this._mcp);
  final AutomationProfileService _service;
  final String _operation;
  final OperationalSessionRequest? _owner;
  final OperationalMcpContext? _mcp;
  String? get _origin => _mcp?.grantId;
  int? get _revision => _mcp?.revision;
  void _identityCheck() {
    if (_owner case final request?) {
      if (!request.belongsTo(_service.sessions) ||
          request.role != OperationalRole.owner ||
          request.method != 'automation.profiles.$_operation' ||
          !request.initialAdmissionProved) {
        throw StateError('FORBIDDEN');
      }
      request.rpcRemaining;
    } else {
      if (!_mcp!.belongsTo(_service.sessions, _service.authority))
        throw StateError('FORBIDDEN');
    }
  }

  void _check() {
    _identityCheck();
    _mcp?.authorize(scope: McpScope.author);
  }

  Future<void> _checkWhenStable(Duration deadline) async {
    _identityCheck();
    await _mcp?.authorizeWhenStable(scope: McpScope.author, deadline: deadline);
    _identityCheck();
  }
}

final class ProfileCatalogOperation {
  ProfileCatalogOperation._(this._service, this._actor, this._input) {
    result = _run();
    result.ignore();
  }
  final AutomationProfileService _service;
  final ProfileCatalogActor _actor;
  ProfileCatalogInput _input;
  final _watch = Stopwatch()..start();
  late final Future<Map<String, Object?>> result;
  bool _retired = false, _admitted = false;
  Duration get _remaining {
    if (!_admitted && (_service._closed || _retired))
      throw StateError('NOT_READY');
    final left =
        _actor._owner?.rpcRemaining ??
        const Duration(seconds: 30) - _watch.elapsed;
    if (left <= Duration.zero) throw StateError('TIMEOUT');
    return left;
  }

  Duration get _proofBudget {
    final left = _remaining;
    return left < const Duration(seconds: 5)
        ? left
        : const Duration(seconds: 5);
  }

  bool _publicationPause(Object error) =>
      error is StateError &&
      error.message == 'STORAGE_BLOCKED' &&
      _service.store.hasPendingMcpAuthorityPublication;

  Future<void> _scope(Duration deadline) async {
    _remaining;
    await _actor._checkWhenStable(deadline);
    _remaining;
  }

  Future<void> _proof() async {
    final budget = _proofBudget, watch = Stopwatch()..start();
    Duration remaining() {
      final left = budget - watch.elapsed, overall = _remaining;
      if (left <= Duration.zero) throw StateError('TIMEOUT');
      return left < overall ? left : overall;
    }

    while (true) {
      await _scope(remaining());
      final actual =
          _actor._owner?.revalidate(
            observeNativeCompletion: _service._observeNative,
          ) ??
          _actor._mcp!.revalidate(
            deadline: remaining(),
            observeNativeCompletion: _service._observeNative,
          );
      _service._observeProof(actual);
      try {
        await actual.timeout(remaining());
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
      remaining();
      try {
        _actor._check();
        return;
      } catch (error) {
        if (!_publicationPause(error)) rethrow;
        await _service.store.waitForMcpAuthority(deadline: remaining());
      }
    }
  }

  Future<T> _read<T>(T Function() read) async {
    while (true) {
      await _proof();
      try {
        _actor._check();
        final result = read();
        _actor._check();
        _remaining;
        return result;
      } catch (error) {
        if (!_publicationPause(error)) rethrow;
        await _service.store.waitForMcpAuthority(deadline: _proofBudget);
      }
    }
  }

  Future<void> cancelInterest() async {
    if (!_admitted) _retired = true;
  }

  Future<Map<String, Object?>> _run() async {
    while (true) {
      await _scope(_proofBudget);
      try {
        // Resolve captured MCP semantics only after a fresh synchronous author
        // check, with no await between this check and the immutable parse.
        _actor._check();
        _input = _input._resolve();
        break;
      } catch (error) {
        if (!_publicationPause(error)) rethrow;
      }
    }
    if (_input.mutation) {
      final budget = _proofBudget;
      return _service.sessions.runAuthorityMutation(
        () async {
          await _proof();
          _remaining;
          _actor._check();
          _admitted = true;
          return _service.store.mutateAutomationProfile(
            _input.command!,
            originGrantId: _actor._origin,
            expectedGrantRevision: _actor._revision,
            clock: _service._clock,
          );
        },
        deadline: budget,
        observeNativeCompletion: _service._observeNative,
      );
    }
    if (_input.operation == 'validate') {
      final started = Stopwatch();
      Duration remainingValidation() {
        final left =
            const Duration(seconds: 1) - _input._parseElapsed - started.elapsed;
        if (left <= Duration.zero) throw StateError('TIMEOUT');
        return left;
      }

      remainingValidation();
      await _proof();
      final body = _input.body;
      if (body == null)
        return _read(
          () => {
            'valid': false,
            'issues': [
              {'field': 'body', 'code': 'VALIDATION'},
            ],
          },
        );
      late final String digest;
      try {
        started.start();
        digest = await body.digest().timeout(remainingValidation());
      } on TimeoutException {
        throw StateError('TIMEOUT');
      }
      started.stop();
      remainingValidation();
      return _read(() {
        started.start();
        final normalized = body.toJson();
        final output = <String, Object?>{
          'valid': true,
          'issues': [],
          'digest': digest,
          'normalizedBody': normalized,
          'normalizedEffects': normalized['steps'],
        };
        started.stop();
        remainingValidation();
        return output;
      });
    }
    final params = _input.params;
    final continuation = params.containsKey('cursor');
    final prepared = await _read(() {
      final snapshot = _service.store.operational.automation;
      final fingerprint = _service._metadataDigest(snapshot);
      late final Map<String, Object?> output;
      switch (_input.operation) {
        case 'list':
          output = _service._list(snapshot, fingerprint, _actor, params);
        case 'get':
          final metadata = snapshot.profiles[params['profileId']];
          if (metadata == null) throw StateError('FORBIDDEN');
          final revision = snapshot
              .revisions['${metadata.id}:${params['revision'] ?? metadata.headRevision}'];
          if (revision == null) throw StateError('FORBIDDEN');
          output = {
            'profile': metadata.toJson(),
            'revision': revision.toJson(),
          };
        case 'compare':
          final id = params['profileId'];
          final left = snapshot.revisions['$id:${params['fromRevision']}'];
          final right = snapshot.revisions['$id:${params['toRevision']}'];
          if (left == null || right == null) throw StateError('FORBIDDEN');
          output = profileCatalogDiff(left.body.toJson(), right.body.toJson());
        default:
          throw StateError('UNSUPPORTED');
      }
      return (fingerprint, output);
    });
    if (ownerServiceProbesEnabled) {
      final budget = _remaining;
      await OwnerServiceProbe.hit(
        OwnerServiceBoundary.afterProfileCatalogSnapshot,
        'automation.profiles.${_input.operation}',
      ).timeout(budget);
    }
    return _read(() {
      final current = _service._metadataDigest(
        _service.store.operational.automation,
      );
      if (current != prepared.$1)
        throw StateError(continuation ? 'CURSOR_EXPIRED' : 'REVISION_CONFLICT');
      return prepared.$2;
    });
  }
}

final class AutomationProfileService {
  AutomationProfileService({
    required this.store,
    required this.custody,
    required this.receiptKey,
    required this.sessions,
    required this.authority,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (!sessions.hasNativePublicationGate || !authority.belongsTo(store))
      throw StateError('NOT_READY');
    final state = store.operational.foundation.state;
    if (receiptKey.workspaceId != state.workspaceId ||
        receiptKey.receiptKeyId != state.receiptKeyId ||
        receiptKey.ownerSid != state.ownerSid ||
        custody.ownerSid != state.ownerSid)
      throw StateError('STORAGE_BLOCKED');
    store.assertAutomationCustody(custody, receiptKey);
  }
  final StateStore store;
  final KeyCustody custody;
  final ReceiptKeyMaterial receiptKey;
  final OperationalSessions sessions;
  final OperationalMcpAuthority authority;
  final DateTime Function() _clock;
  final _active = <ProfileCatalogOperation>{};
  final _proofs = <Future<void>>{};
  final _nativeCompletions = <Future<void>>{};
  bool _nativeFailure = false;
  bool _closed = false;
  Future<void>? _closing;
  void _ready() {
    if (_closed) throw StateError('NOT_READY');
  }

  ProfileCatalogActor ownerActor(
    OperationalSessionRequest request,
    String operation,
  ) {
    final actor = ProfileCatalogActor._(this, operation, request, null);
    actor._check();
    _ready();
    return actor;
  }

  ProfileCatalogActor mcpActor(
    OperationalMcpContext context,
    String operation,
  ) {
    final actor = ProfileCatalogActor._(this, operation, null, context);
    actor._identityCheck();
    _ready();
    return actor;
  }

  ProfileCatalogOperation start(
    ProfileCatalogActor actor,
    ProfileCatalogInput input,
  ) {
    if (!identical(actor._service, this) || actor._operation != input.operation)
      throw StateError('FORBIDDEN');
    actor._identityCheck();
    _ready();
    if (_active.length >= 128) throw StateError('RESOURCE_LIMIT');
    final operation = ProfileCatalogOperation._(this, actor, input);
    _active.add(operation);
    operation.result.then<void>(
      (_) {
        _active.remove(operation);
      },
      onError: (Object _, StackTrace __) {
        _active.remove(operation);
      },
    );
    return operation;
  }

  void _observeProof(Future<void> work) {
    _proofs.add(work);
    work.then<void>(
      (_) {
        _proofs.remove(work);
      },
      onError: (Object _, StackTrace __) {
        _proofs.remove(work);
      },
    );
  }

  void _observeNative(Future<void> actual) {
    _nativeCompletions.add(actual);
    actual.then<void>(
      (_) {
        _nativeCompletions.remove(actual);
      },
      onError: (Object _, StackTrace __) {
        _nativeFailure = true;
        _nativeCompletions.remove(actual);
      },
    );
  }

  String _metadataDigest(AutomationSnapshot snapshot) {
    final ids = snapshot.profiles.keys.toList()..sort();
    final bytes = StrictCodec().canonical({
      'items': [for (final id in ids) snapshot.profiles[id]!.toJson()],
    });
    final digest = const DartSha256().hashSync(bytes);
    return digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _base64(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');
  List<int> _unbase64(String text) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text))
      throw const FormatException('VALIDATION');
    final decoded = base64Url.decode(base64Url.normalize(text));
    if (_base64(decoded) != text) throw const FormatException('VALIDATION');
    return decoded;
  }

  String _mac(Map<String, Object?> payload) => _base64(
    base64.decode(
      custody.receiptDigestSync(receiptKey, {
        'purpose': 'profile-catalog-cursor-v1',
        'payload': payload,
      }),
    ),
  );
  bool _equal(String left, String right) {
    final a = ascii.encode(left), b = ascii.encode(right);
    var difference = a.length ^ b.length;
    final length = a.length > b.length ? a.length : b.length;
    for (var n = 0; n < length; n++) {
      difference |= (n < a.length ? a[n] : 0) ^ (n < b.length ? b[n] : 0);
    }
    return difference == 0;
  }

  Map<String, Object?> _list(
    AutomationSnapshot snapshot,
    String fingerprint,
    ProfileCatalogActor actor,
    Map<String, Object?> params,
  ) {
    final archived = params['includeArchived'] as bool? ?? false;
    final limit = params['limit'] as int? ?? 50;
    final ids =
        snapshot.profiles.values
            .where((p) => archived || !p.archived)
            .map((p) => p.id)
            .toList()
          ..sort();
    final now = _clock().toUtc().millisecondsSinceEpoch;
    var offset = 0;
    if (params['cursor'] case final String token) {
      try {
        if (token.length > 512) throw const FormatException();
        final parts = token.split('.');
        if (parts.length != 2) throw const FormatException();
        final bytes = _unbase64(parts[0]);
        final payload = StrictCodec().decode(bytes, maxBytes: 512);
        requireFields(payload, {'v', 'w', 'g', 'r', 'a', 'h', 'l', 't'});
        _unbase64(parts[1]);
        final issued = payload['t'];
        if (!_equal(parts[1], _mac(payload)) ||
            payload['v'] != 1 ||
            payload['v'] is! int ||
            payload['w'] != store.state.workspaceId ||
            payload['g'] != actor._origin ||
            payload['r'] != (actor._revision ?? 0) ||
            payload['r'] is! int ||
            payload['a'] != archived ||
            payload['h'] != fingerprint ||
            issued is! int ||
            issued > now ||
            now >= issued + 300000 ||
            payload['l'] is! String ||
            !ids.contains(payload['l']))
          throw const FormatException();
        // Reject non-canonical payload encodings too, not just padding variants.
        if (_base64(StrictCodec().canonical(payload)) != parts[0])
          throw const FormatException();
        offset = ids.indexOf(payload['l'] as String) + 1;
      } catch (_) {
        throw StateError('CURSOR_EXPIRED');
      }
    }
    final selected = ids.skip(offset).take(limit).toList();
    String? next;
    if (offset + selected.length < ids.length) {
      final payload = <String, Object?>{
        'v': 1,
        'w': store.state.workspaceId,
        'g': actor._origin,
        'r': actor._revision ?? 0,
        'a': archived,
        'h': fingerprint,
        'l': selected.last,
        't': now,
      };
      next = '${_base64(StrictCodec().canonical(payload))}.${_mac(payload)}';
      if (next.length > 512) throw StateError('RESOURCE_LIMIT');
    }
    return {
      'items': [for (final id in selected) snapshot.profiles[id]!.toJson()],
      if (next != null) 'nextCursor': next,
    };
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _closed = true;
    for (final operation in _active.toList()) {
      if (!operation._admitted) operation._retired = true;
    }
    return _closing = () async {
      while (_active.isNotEmpty ||
          _proofs.isNotEmpty ||
          _nativeCompletions.isNotEmpty) {
        await Future.wait<void>([
          for (final operation in _active.toList())
            operation.result.then<void>(
              (_) {},
              onError: (Object _, StackTrace __) {},
            ),
          for (final proof in _proofs.toList())
            proof.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
          for (final actual in _nativeCompletions.toList())
            actual.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
        ]);
      }
      if (_nativeFailure) throw StateError('SERVICE_UNAVAILABLE');
    }();
  }
}
