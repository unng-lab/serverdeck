import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:serverdeck_protocol/codec.dart';
import 'package:serverdeck_protocol/executor_enrollment.dart';
import 'package:serverdeck_protocol/executor_owner.dart';
import 'package:serverdeck_protocol/validation.dart';

import '../platform/ports.dart';
import 'key_custody.dart';

/// Captured input, bound to one repository. It grants no owner/target authority.
final class ExecutorEnrollmentMutation {
  ExecutorEnrollmentMutation._(
    this._issuer,
    this.requestId,
    this.method,
    this._input,
    this._digest,
  );
  final ExecutorEnrollmentStore _issuer;
  final String requestId, method, _digest;
  final Map<String, Object?> _input;
}

/// Protected schema3 sidecar with exact outer format2 and inner enrollment1.
/// The host owns the lease and serializes this primitive through its shared
/// writer queue. The owner adapter retains fresh target proof through completion.
/// Neither persisted metadata nor a captured mutation grants permission to act.
final class ExecutorEnrollmentStore {
  ExecutorEnrollmentStore({
    required this.files,
    required this.lease,
    required this.custody,
    required this.key,
    required void Function() requireReady,
    required void Function() onStorageBlocked,
  }) : _requireReady = requireReady,
       _onStorageBlocked = onStorageBlocked;

  final ProtectedFiles files;
  final WorkspaceLease lease;
  final KeyCustody custody;
  final ReceiptKeyMaterial key;
  final void Function() _requireReady, _onStorageBlocked;
  bool _blocked = false, _running = false;
  String get _directory =>
      p.join(files.root, 'ServerDeckNext', 'v1', 'workspaces', 'default');
  String get _path => p.join(_directory, 'executor-enrollments.json');

  Never _poison() {
    if (!_blocked) {
      _blocked = true;
      try {
        _onStorageBlocked();
      } catch (_) {
        /* Report only a fixed category. */
      }
    }
    throw StateError('STORAGE_BLOCKED');
  }

  void _live() {
    if (_blocked) throw StateError('STORAGE_BLOCKED');
    _requireReady();
    try {
      if (!lease.isHeld ||
          lease.workspaceSlot != 'default' ||
          lease.ownerIdentity != key.ownerSid ||
          files.ownerIdentity != key.ownerSid ||
          custody.ownerSid != key.ownerSid)
        _poison();
      files.requirePath(files.root);
      custody.receiptDigestSync(key, {
        'purpose': 'executor-enrollment-liveness-v1',
      });
    } catch (_) {
      _poison();
    }
  }

  void _parents() {
    var path = files.root;
    for (final segment in ['ServerDeckNext', 'v1', 'workspaces', 'default']) {
      path = p.join(path, segment);
      files.requirePath(path);
      if (files.kind(path) != ProtectedPathKind.directory) _poison();
      files.requireOwnerOnly(path);
    }
    files.requirePath(_path);
  }

  Future<T> _operation<T>(Future<T> Function() action) {
    _live();
    if (_running) throw StateError('NOT_READY');
    _running = true;
    return Future<T>.sync(action).whenComplete(() {
      _running = false;
    });
  }

  ExecutorEnrollmentMutation prepare({
    required String requestId,
    required String method,
    required Map<String, Object?> input,
  }) {
    _live();
    requireUuid(requestId);
    if (!const {'executor.confirm', 'executor.revoke'}.contains(method))
      throw StateError('UNSUPPORTED');
    requireFields(
      input,
      method == 'executor.confirm'
          ? {'profileId', 'challengeId', 'hostId'}
          : {'profileId'},
    );
    for (final value in input.values) {
      requireUuid(value);
    }
    final captured = Map<String, Object?>.unmodifiable(input);
    final digest = custody.receiptDigestSync(key, {
      'purpose': 'executor-enrollment-mutation-v1',
      'workspaceId': key.workspaceId,
      'method': method,
      'input': captured,
    });
    return ExecutorEnrollmentMutation._(
      this,
      requestId,
      method,
      captured,
      digest,
    );
  }

  void _bound(ExecutorEnrollmentMutation command) {
    if (!identical(command._issuer, this)) throw StateError('FORBIDDEN');
  }

  Future<Map<String, ExecutorEnrollment>> read() =>
      _operation(() async => Map.unmodifiable((await _read()).records));

  Future<Map<String, Object?>?> receipt(ExecutorEnrollmentMutation command) {
    _bound(command);
    return _operation(() async => _replay(await _read(), command));
  }

  Future<Map<String, Object?>> mutate(
    ExecutorEnrollmentMutation command, {
    required ExecutorEnrollment? enrollment,
    required Future<void> Function() revalidate,
  }) {
    _bound(command);
    final server = command._input['profileId'] as String,
        method = command.method;
    if (method == 'executor.confirm' &&
        (enrollment == null ||
            enrollment.workspaceId != key.workspaceId ||
            enrollment.serverId != server ||
            enrollment.hostId != command._input['hostId']))
      throw StateError('FORBIDDEN');
    if (method == 'executor.revoke' && enrollment != null)
      throw StateError('VALIDATION');
    return _operation(() async {
      await revalidate();
      _live();
      final document = await _read();
      final replay = _replay(document, command);
      if (replay != null) return replay;
      if (document.receipts.length >= 10000) throw StateError('RESOURCE_LIMIT');
      final before = document.records[server];
      final Map<String, Object?> result;
      if (method == 'executor.confirm') {
        if (before == null && document.records.length >= 250)
          throw StateError('RESOURCE_LIMIT');
        final previous = before == null
            ? null
            : ({...before.toJson()}..remove('createdAt'));
        final proposed = {...enrollment!.toJson()}..remove('createdAt');
        final same =
            previous != null &&
            _same(
              StrictCodec().canonical(previous),
              StrictCodec().canonical(proposed),
            );
        document.records[server] = same ? before! : enrollment;
        result = {
          'profileId': server,
          'enrollment': document.records[server]!.toJson(),
        };
      } else {
        result = {
          'profileId': server,
          'revoked': document.records.remove(server) != null,
        };
      }
      document.receipts[command.requestId] = {
        'requestId': command.requestId,
        'method': method,
        'requestDigest': command._digest,
        'result': captureExecutorOwnerResult(method, result),
      };
      await revalidate();
      _live();
      await _publish(document);
      return result;
    });
  }

  Map<String, Object?>? _replay(
    _Document document,
    ExecutorEnrollmentMutation command,
  ) {
    final receipt = document.receipts[command.requestId];
    if (receipt == null) return null;
    if (!_same(
      base64.decode(receipt['requestDigest'] as String),
      base64.decode(command._digest),
    )) {
      throw StateError('IDEMPOTENCY_CONFLICT');
    }
    // Historical ACK: never restore its binding or refresh a challenge.
    return captureExecutorOwnerResult(
      receipt['method'] as String,
      receipt['result'] as Map<String, Object?>,
    );
  }

  Future<void> _publish(_Document values) async {
    final document = <String, Object?>{
      'format': 2,
      'workspaceId': key.workspaceId,
      'receiptKeyId': key.receiptKeyId,
      'records': [
        for (final id in values.records.keys.toList()..sort())
          values.records[id]!.toJson(),
      ],
      'receipts': [
        for (final id in values.receipts.keys.toList()..sort())
          values.receipts[id],
      ],
    };
    final List<int> encoded;
    try {
      encoded = StrictCodec().encode({
        'document': document,
        'mac': custody.receiptDigestSync(key, {
          'purpose': 'executor-enrollments-v1',
          'document': document,
        }),
      }, maxBytes: 64 * 1024 * 1024);
    } on FormatException {
      throw StateError('RESOURCE_LIMIT');
    }
    try {
      _live();
      _parents();
      await files.replaceFile(_path, encoded);
      _live();
      final actual = await files.readFile(_path, maxBytes: 64 * 1024 * 1024);
      _live();
      if (!_same(encoded, actual)) _poison();
      await _read();
    } catch (_) {
      _poison();
    }
  }

  Future<_Document> _read() async {
    _live();
    try {
      _parents();
      final kind = files.kind(_path);
      if (kind == ProtectedPathKind.absent) return _Document({}, {});
      if (kind != ProtectedPathKind.file) _poison();
      files.requireOwnerOnly(_path);
      final bytes = await files.readFile(_path, maxBytes: 64 * 1024 * 1024);
      _live();
      final value = StrictCodec().decode(bytes, maxBytes: 64 * 1024 * 1024);
      requireFields(value, {'document', 'mac'});
      final document = value['document'];
      if (document is! Map<String, Object?> || value['mac'] is! String)
        _poison();
      if (document['format'] is! int || document['format'] != 2) _poison();
      requireFields(document, {
        'format',
        'workspaceId',
        'receiptKeyId',
        'records',
        'receipts',
      });
      if (document['workspaceId'] != key.workspaceId ||
          document['receiptKeyId'] != key.receiptKeyId)
        _poison();
      final expected = base64.decode(
        custody.receiptDigestSync(key, {
          'purpose': 'executor-enrollments-v1',
          'document': document,
        }),
      );
      if (!_same(expected, base64.decode(value['mac'] as String))) _poison();
      final rows = document['records'];
      if (rows is! List || rows.length > 250) _poison();
      final records = <String, ExecutorEnrollment>{};
      for (final row in rows) {
        if (row is! Map<String, Object?>) _poison();
        final record = ExecutorEnrollment.fromJson(row);
        if (record.workspaceId != key.workspaceId ||
            records.containsKey(record.serverId))
          _poison();
        records[record.serverId] = record;
      }
      final receiptRows = document['receipts'];
      if (receiptRows is! List || receiptRows.length > 10000) _poison();
      final receipts = <String, Map<String, Object?>>{};
      for (final row in receiptRows) {
        if (row is! Map<String, Object?>) _poison();
        requireFields(row, {'requestId', 'method', 'requestDigest', 'result'});
        final id = requireUuid(row['requestId']), method = row['method'];
        final digest = row['requestDigest'], ack = row['result'];
        if (!const {'executor.confirm', 'executor.revoke'}.contains(method) ||
            digest is! String ||
            base64.encode(base64.decode(digest)) != digest ||
            base64.decode(digest).length != 32 ||
            ack is! Map<String, Object?> ||
            receipts.containsKey(id))
          _poison();
        final captured = captureExecutorOwnerResult(method as String, ack);
        final bound = captured['enrollment'];
        if (bound is Map<String, Object?> &&
            bound['workspaceId'] != key.workspaceId)
          _poison();
        receipts[id] = {...row, 'result': captured};
      }
      return _Document(records, receipts);
    } catch (_) {
      _poison();
    }
  }
}

final class _Document {
  _Document(this.records, this.receipts);
  final Map<String, ExecutorEnrollment> records;
  final Map<String, Map<String, Object?>> receipts;
}

bool _same(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  for (var i = 0; i < left.length; i++) {
    difference |= left[i] ^ (i < right.length ? right[i] : 0);
  }
  return difference == 0;
}
