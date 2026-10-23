part of 'state_store.dart';

/// Protected owner-confirmed helper metadata. No SSH credentials or grant
/// secrets are stored here; a binding never overrides current target/authority.
extension ExecutorEnrollments on StateStore {
  String get _executorEnrollmentPath => p.join(
    _operationalRoot!,
    'ServerDeckNext',
    'v1',
    'workspaces',
    'default',
    'executor-enrollments.json',
  );

  Future<Map<String, ExecutorEnrollment>> readExecutorEnrollments() =>
      _queueTrustedMetadata(
        () async => (await _readExecutorDocument()).records,
      );

  Future<Map<String, Object?>?> readExecutorEnrollmentReceipt({
    required String requestId,
    required String method,
    required Map<String, Object?> input,
  }) {
    final command = _captureExecutorMutation(requestId, method, input);
    return _queueTrustedMetadata(() async {
      final document = await _readExecutorDocument();
      return _executorReplay(document, requestId, command);
    });
  }

  /// The owner adapter retains the native target fence and drains affected
  /// streams before entry. Record and result are published in ONE protected
  /// replacement. A lost ACK can therefore never repeat an enrollment effect.
  Future<Map<String, Object?>> mutateExecutorEnrollment({
    required String requestId,
    required String method,
    required Map<String, Object?> input,
    required ExecutorEnrollment? enrollment,
    required Future<void> Function() revalidate,
  }) {
    final command = _captureExecutorMutation(requestId, method, input);
    final server = input['profileId'] as String;
    if (method == 'executor.confirm' &&
        (enrollment == null ||
            enrollment.workspaceId != _state.workspaceId ||
            enrollment.serverId != server ||
            enrollment.hostId != input['hostId']))
      throw StateError('FORBIDDEN');
    if (method == 'executor.revoke' && enrollment != null)
      throw StateError('VALIDATION');
    return _queueTrustedMetadata(() async {
      await revalidate();
      _ensure();
      final document = await _readExecutorDocument();
      final replay = _executorReplay(document, requestId, command);
      if (replay != null) return replay;
      if (document.receipts.length >= 10000) throw StateError('RESOURCE_LIMIT');
      final records = document.records;
      final before = records[server];
      final Map<String, Object?> result;
      if (method == 'executor.confirm') {
        if (before == null && records.length >= 250)
          throw StateError('RESOURCE_LIMIT');
        final old = before?.toJson();
        final proposed = {...enrollment!.toJson()}..remove('createdAt');
        final previous = old == null ? null : ({...old}..remove('createdAt'));
        final same =
            previous != null &&
            _sameExecutorBytes(
              StrictCodec().canonical(previous),
              StrictCodec().canonical(proposed),
            );
        records[server] = same ? before! : enrollment;
        result = {'profileId': server, 'enrollment': records[server]!.toJson()};
      } else {
        result = {
          'profileId': server,
          'revoked': records.remove(server) != null,
        };
      }
      document.receipts[requestId] = {
        'requestId': requestId,
        'method': method,
        'requestDigest': command,
        'result': captureExecutorOwnerResult(method, result),
      };
      await revalidate();
      _ensure();
      await _publishExecutorEnrollments(document);
      return result;
    });
  }

  String _captureExecutorMutation(
    String requestId,
    String method,
    Map<String, Object?> input,
  ) {
    _ensure();
    trustedOperational;
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
    return _custody.receiptDigestSync(_receiptKey, {
      'purpose': 'executor-enrollment-mutation-v1',
      'workspaceId': _state.workspaceId,
      'method': method,
      'input': input,
    });
  }

  Map<String, Object?>? _executorReplay(
    _ExecutorEnrollmentDocument document,
    String requestId,
    String digest,
  ) {
    final receipt = document.receipts[requestId];
    if (receipt == null) return null;
    if (!_sameExecutorBytes(
      base64.decode(receipt['requestDigest'] as String),
      base64.decode(digest),
    ))
      throw StateError('IDEMPOTENCY_CONFLICT');
    // Historical ACK only: never restore its binding or refresh a challenge.
    return captureExecutorOwnerResult(
      receipt['method'] as String,
      receipt['result'] as Map<String, Object?>,
    );
  }

  Future<void> _publishExecutorEnrollments(
    _ExecutorEnrollmentDocument values,
  ) async {
    final document = <String, Object?>{
      'format': 2,
      'workspaceId': _state.workspaceId,
      'receiptKeyId': _receiptKey.receiptKeyId,
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
        'mac': _custody.receiptDigestSync(_receiptKey, {
          'purpose': 'executor-enrollments-v1',
          'document': document,
        }),
      }, maxBytes: 64 * 1024 * 1024);
    } on FormatException {
      throw StateError('RESOURCE_LIMIT');
    }
    try {
      await replaceProtectedFile(
        _operationalRoot!,
        _executorEnrollmentPath,
        _state.ownerSid,
        encoded,
      );
      final actual = await readProtectedFile(
        _operationalRoot,
        _executorEnrollmentPath,
        _state.ownerSid,
        maxBytes: 64 * 1024 * 1024,
      );
      if (!_sameExecutorBytes(encoded, actual))
        throw StateError('STORAGE_BLOCKED');
      await _readExecutorDocument();
    } catch (_) {
      // Replacement may have committed. Never continue from an uncertain
      // old in-memory binding; restart must authenticate the actual file.
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }

  Future<T> _queueTrustedMetadata<T>(Future<T> Function() action) {
    _ensure();
    trustedOperational;
    if (_closing || _operationalRoot == null) throw StateError('NOT_READY');
    if (_pendingAutomation.length + _pendingFoundation >= 32)
      throw StateError('RESOURCE_LIMIT');
    _pendingFoundation++;
    final run = _tail.then((_) async {
      _ensure();
      return action();
    });
    _tail = run.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return run.whenComplete(() => _pendingFoundation--);
  }

  Future<_ExecutorEnrollmentDocument> _readExecutorDocument() async {
    _ensure();
    trustedOperational;
    final path = _executorEnrollmentPath;
    if (FileSystemEntity.typeSync(path, followLinks: false) ==
        FileSystemEntityType.notFound)
      return _ExecutorEnrollmentDocument({}, {});
    try {
      final bytes = await readProtectedFile(
        _operationalRoot!,
        path,
        _state.ownerSid,
        maxBytes: 64 * 1024 * 1024,
      );
      final value = StrictCodec().decode(bytes, maxBytes: 64 * 1024 * 1024);
      requireFields(value, {'document', 'mac'});
      final document = value['document'];
      if (document is! Map<String, Object?> || value['mac'] is! String)
        throw StateError('STORAGE_BLOCKED');
      final format = document['format'];
      if (format is! int || !const {1, 2}.contains(format))
        throw StateError('STORAGE_BLOCKED');
      requireFields(document, {
        'format',
        'workspaceId',
        'receiptKeyId',
        'records',
        if (format == 2) 'receipts',
      });
      if (document['workspaceId'] != _state.workspaceId ||
          document['receiptKeyId'] != _receiptKey.receiptKeyId)
        throw StateError('STORAGE_BLOCKED');
      final expected = base64.decode(
        _custody.receiptDigestSync(_receiptKey, {
          'purpose': 'executor-enrollments-v1',
          'document': document,
        }),
      );
      final actual = base64.decode(value['mac'] as String);
      if (!_sameExecutorBytes(expected, actual))
        throw StateError('STORAGE_BLOCKED');
      final rows = document['records'];
      if (rows is! List || rows.length > 250)
        throw StateError('STORAGE_BLOCKED');
      final result = <String, ExecutorEnrollment>{};
      for (final row in rows) {
        if (row is! Map<String, Object?>) throw StateError('STORAGE_BLOCKED');
        final enrollment = ExecutorEnrollment.fromJson(row);
        if (enrollment.workspaceId != _state.workspaceId ||
            result.containsKey(enrollment.serverId))
          throw StateError('STORAGE_BLOCKED');
        result[enrollment.serverId] = enrollment;
      }
      final receipts = <String, Map<String, Object?>>{};
      if (format == 2) {
        final rows = document['receipts'];
        if (rows is! List || rows.length > 10000)
          throw StateError('STORAGE_BLOCKED');
        for (final row in rows) {
          if (row is! Map<String, Object?>) throw StateError('STORAGE_BLOCKED');
          requireFields(row, {
            'requestId',
            'method',
            'requestDigest',
            'result',
          });
          final id = requireUuid(row['requestId']);
          final method = row['method'];
          final requestDigest = row['requestDigest'];
          final ack = row['result'];
          if (!const {'executor.confirm', 'executor.revoke'}.contains(method) ||
              requestDigest is! String ||
              base64.encode(base64.decode(requestDigest)) != requestDigest ||
              base64.decode(requestDigest).length != 32 ||
              ack is! Map<String, Object?> ||
              receipts.containsKey(id))
            throw StateError('STORAGE_BLOCKED');
          final captured = captureExecutorOwnerResult(method as String, ack);
          final bound = captured['enrollment'];
          if (bound is Map<String, Object?> &&
              bound['workspaceId'] != _state.workspaceId)
            throw StateError('STORAGE_BLOCKED');
          receipts[id] = {...row, 'result': captured};
        }
      }
      return _ExecutorEnrollmentDocument(result, receipts);
    } catch (_) {
      _blocked = true;
      throw StateError('STORAGE_BLOCKED');
    }
  }
}

final class _ExecutorEnrollmentDocument {
  _ExecutorEnrollmentDocument(this.records, this.receipts);
  final Map<String, ExecutorEnrollment> records;
  final Map<String, Map<String, Object?>> receipts;
}

bool _sameExecutorBytes(List<int> left, List<int> right) {
  var difference = left.length ^ right.length;
  for (var i = 0; i < left.length; i++)
    difference |= left[i] ^ (i < right.length ? right[i] : 0);
  return difference == 0;
}
