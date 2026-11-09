import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';
import '../domain/receipt_book.dart';
import '../runtime/capability.dart';
import '../storage/domain_repository.dart';
import '../storage/records.dart';
import 'software_models.dart';

/// Local metadata only. All actors share the root's gate and repository.
final class SoftwareOwner implements RuntimeCapability, Listenable {
  SoftwareOwner({
    required this.gate,
    required this.repository,
    required this.receipts,
    required this.newId,
    required this.utcNow,
  });
  final DomainCommandGate gate;
  final DomainRepository repository;
  final ReceiptBook receipts;
  final String Function() newId;
  final int Function() utcNow;
  final _notifier = ValueNotifier<int>(0);
  final _pending = <Future<void>>{};
  bool _stopped = false, _disposed = false;
  @override
  String get id => 'software';
  @override
  void addListener(VoidCallback listener) => _notifier.addListener(listener);
  @override
  void removeListener(VoidCallback listener) =>
      _notifier.removeListener(listener);
  void _admit() {
    if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
  }

  static Never _invalid([OperationField field = OperationField.request]) =>
      throw OperationFailure(FailureCode.invalidArgument, field: field);
  static void _uuid(
    String id, [
    OperationField field = OperationField.profileId,
  ]) {
    if (!isCanonicalUuid(id)) _invalid(field);
  }

  static Profile _profile(DomainRead r, String id) =>
      r.profile(id) ??
      (throw const OperationFailure(FailureCode.profileNotFound));
  static SoftwareCardRecord _card(
    DomainRead r,
    String id, {
    String? profileId,
  }) {
    final value = r.softwareCard(id);
    if (value == null || (profileId != null && value.profileId != profileId)) {
      throw const OperationFailure(FailureCode.softwareNotFound);
    }
    return value;
  }

  static void _revision(int revision) {
    if (revision < 1 || revision > 9007199254740991)
      _invalid(OperationField.expectedRevision);
  }

  String _newId() {
    final value = newId();
    if (!isCanonicalUuid(value))
      throw const OperationFailure(FailureCode.storageUnavailable);
    return value;
  }

  Future<OperationResult<SoftwareValue>> get(Actor actor, String softwareId) =>
      gate.submit(
        actor,
        (context) => context.read(
          () => repository.read((r) {
            _admit();
            _uuid(softwareId, OperationField.softwareId);
            final card = _card(r, softwareId),
                profile = _profile(r, card.profileId);
            return SoftwareValue(
              SoftwareCardView(
                card,
                currentTarget: card.endpointId == profile.endpointId,
              ),
            );
          }),
        ),
      );

  Future<OperationResult<SoftwareValue>> list(
    Actor actor,
    String profileId, {
    int limit = 25,
    String? cursor,
  }) => gate.submit(
    actor,
    (context) => context.read(
      () => repository.read((r) {
        _admit();
        _uuid(profileId);
        final profile = _profile(r, profileId);
        final revision = r.settings.profilesListRevision;
        final offset = _offset(
          cursor,
          'cards',
          profileId,
          null,
          revision,
          limit,
        );
        final values = r.softwareCards(
          profileId,
          offset: offset,
          limit: limit + 1,
        );
        final items = <SoftwareProjection>[];
        for (final record in values.take(limit)) {
          final item = SoftwareCardView(
            record,
            currentTarget: record.endpointId == profile.endpointId,
          );
          if (!_fits([...items, item])) break;
          items.add(item);
        }
        return SoftwareValue(
          SoftwarePage(
            items,
            values.length > items.length
                ? _cursor(
                    'cards',
                    profileId,
                    null,
                    revision,
                    offset + items.length,
                  )
                : null,
          ),
        );
      }),
    ),
  );

  static int _offset(
    String? cursor,
    String kind,
    String profileId,
    String? softwareId,
    int revision,
    int limit,
  ) {
    if (limit < 1 || limit > 100) _invalid(OperationField.limit);
    if (cursor == null) return 0;
    try {
      if (cursor.length > 512) throw const FormatException();
      final bytes = base64Url.decode(cursor);
      if (base64Url.encode(bytes) != cursor) throw const FormatException();
      final parsed = jsonDecode(utf8.decode(bytes));
      if (parsed is! Map<String, dynamic> ||
          parsed.length != 6 ||
          jsonEncode(parsed) != utf8.decode(bytes) ||
          parsed['v'] is! int ||
          parsed['v'] != 1 ||
          parsed['kind'] != kind ||
          parsed['profileId'] != profileId ||
          parsed['softwareId'] != softwareId ||
          parsed['snapshotRevision'] is! int ||
          (parsed['snapshotRevision'] as int) < 1 ||
          (parsed['snapshotRevision'] as int) > 9007199254740991 ||
          parsed['offset'] is! int ||
          (parsed['offset'] as int) < 0 ||
          (parsed['offset'] as int) > softwareCardLimit ||
          parsed.keys.any(
            (k) => !const {
              'v',
              'kind',
              'profileId',
              'softwareId',
              'snapshotRevision',
              'offset',
            }.contains(k),
          )) {
        throw const FormatException();
      }
      if (parsed['snapshotRevision'] != revision)
        throw const OperationFailure(
          FailureCode.conflict,
          field: OperationField.cursor,
        );
      return parsed['offset'] as int;
    } on OperationFailure {
      rethrow;
    } catch (_) {
      _invalid(OperationField.cursor);
    }
  }

  static String _cursor(
    String kind,
    String profileId,
    String? softwareId,
    int revision,
    int offset,
  ) => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'kind': kind,
        'profileId': profileId,
        'softwareId': softwareId,
        'snapshotRevision': revision,
        'offset': offset,
      }),
    ),
  );
  // Reserve envelope/cursor/meta/escaping overhead. Router additionally checks its
  // complete duplicated text+structured response against the shared 1MiB cap.
  static bool _fits(List<SoftwareProjection> values) {
    final json = {
      'ok': true,
      'value': SoftwarePage(values, null).toJson(),
      'meta': {'dataRevision': 9007199254740991, 'ownerEpoch': 'x' * 36},
    };
    final reply = {
      'jsonrpc': '2.0',
      'id': 'x' * 128,
      'result': {
        'content': [
          {'type': 'text', 'text': jsonEncode(json)},
        ],
        'structuredContent': json,
        'isError': false,
      },
    };
    return utf8.encode(jsonEncode(reply)).length <= 1048576 - 8192;
  }

  Future<OperationResult<MutationValue>> save(
    Actor actor,
    String profileId,
    SoftwareCardInput card, {
    String? softwareId,
    int? expectedRevision,
    required String mutationId,
  }) => _mutate(
    actor,
    ReceiptMethod.saveSoftware,
    mutationId,
    {
      'profileId': profileId,
      if (softwareId != null) 'softwareId': softwareId,
      if (expectedRevision != null) 'expectedRevision': expectedRevision,
      'card': card.receiptPayload,
    },
    (r) {
      _uuid(profileId);
      if ((softwareId == null) != (expectedRevision == null)) _invalid();
      final profile = _profile(r, profileId);
      SoftwareCardRecord record;
      String kind;
      final changed = <String>[];
      if (softwareId == null) {
        if (r.softwareCardCount() >= softwareCardLimit ||
            r.softwareCardCount(profileId: profileId) >=
                softwareProfileCardLimit) {
          throw const OperationFailure(FailureCode.resourceExhausted);
        }
        record = SoftwareCardRecord()
          ..softwareId = _newId()
          ..profileId = profileId
          ..endpointId = profile.endpointId
          ..host = profile.normalizedHost
          ..port = profile.port
          ..username = profile.username
          ..createdAt = utcNow();
        if (r.softwareCard(record.softwareId) != null)
          throw const OperationFailure(FailureCode.conflict);
        kind = 'created';
      } else {
        _uuid(softwareId, OperationField.softwareId);
        _revision(expectedRevision!);
        record = _card(r, softwareId, profileId: profileId);
        if (record.revision != expectedRevision ||
            record.endpointId != profile.endpointId) {
          throw const OperationFailure(FailureCode.conflict);
        }
        final before = SoftwareCardView(
          record,
          currentTarget: true,
        ).card.toJson();
        for (final field in card.toJson().keys) {
          if (jsonEncode(before[field]) != jsonEncode(card.toJson()[field]))
            changed.add(field);
        }
        record.revision = nextRevision(record.revision);
        kind = 'updated';
      }
      record
        ..name = card.name
        ..version = card.version
        ..service = card.service
        ..dataPaths = List.of(card.dataPaths)
        ..configPaths = List.of(card.configPaths)
        ..updatedAt = utcNow();
      SoftwareCardView(record, currentTarget: true);
      r.putSoftwareCard(record);
      _event(r, actor, record, kind, changed);
      return MutationValue(
        entityId: record.softwareId,
        revision: record.revision,
      );
    },
  );

  Future<OperationResult<MutationValue>> delete(
    Actor actor,
    String profileId,
    String softwareId, {
    required int expectedRevision,
    required String mutationId,
  }) => _mutate(
    actor,
    ReceiptMethod.deleteSoftware,
    mutationId,
    {
      'profileId': profileId,
      'softwareId': softwareId,
      'expectedRevision': expectedRevision,
    },
    (r) {
      _uuid(profileId);
      _uuid(softwareId, OperationField.softwareId);
      _revision(expectedRevision);
      _profile(r, profileId);
      final record = _card(r, softwareId, profileId: profileId);
      if (record.revision != expectedRevision)
        throw const OperationFailure(FailureCode.conflict);
      final revision = nextRevision(record.revision);
      r.deleteSoftwareCard(softwareId);
      _event(r, actor, record, 'deleted', []);
      return MutationValue(entityId: softwareId, revision: revision);
    },
  );

  Future<OperationResult<MutationValue>> addNote(
    Actor actor,
    String profileId,
    SoftwareNoteInput note, {
    String? softwareId,
    required String mutationId,
  }) => _mutate(
    actor,
    ReceiptMethod.addSoftwareNote,
    mutationId,
    {
      'profileId': profileId,
      if (softwareId != null) 'softwareId': softwareId,
      'action': note.action,
      'summary': note.summary,
      'outcome': note.outcome,
    },
    (r) {
      _uuid(profileId);
      final profile = _profile(r, profileId);
      SoftwareCardRecord? card;
      if (softwareId != null) {
        _uuid(softwareId, OperationField.softwareId);
        card = _card(r, softwareId, profileId: profileId);
        if (card.endpointId != profile.endpointId)
          throw const OperationFailure(FailureCode.conflict);
      }
      final event = SoftwareEventRecord()
        ..eventId = _newId()
        ..profileId = profileId
        ..endpointId = card?.endpointId ?? profile.endpointId
        ..host = card?.host ?? profile.normalizedHost
        ..port = card?.port ?? profile.port
        ..username = card?.username ?? profile.username
        ..softwareId = softwareId
        ..softwareName = card?.name
        ..kind = 'note'
        ..action = note.action
        ..summary = note.summary
        ..outcome = note.outcome
        ..actorKind = actor is McpActor ? 'mcp' : 'ui'
        ..clientId = actor is McpActor ? actor.clientId : null
        ..createdAt = utcNow();
      SoftwareEventView(event);
      r.putSoftwareEvent(event);
      return MutationValue(entityId: event.eventId, revision: 1);
    },
  );

  Future<OperationResult<SoftwareValue>> history(
    Actor actor,
    String profileId, {
    String? softwareId,
    int limit = 25,
    String? cursor,
  }) => gate.submit(
    actor,
    (context) => context.read(
      () => repository.read((r) {
        _admit();
        _uuid(profileId);
        _profile(r, profileId);
        if (softwareId != null) _uuid(softwareId, OperationField.softwareId);
        final revision = r.settings.profilesListRevision;
        final offset = _offset(
          cursor,
          'history',
          profileId,
          softwareId,
          revision,
          limit,
        );
        final values = r.softwareEvents(
          profileId,
          softwareId: softwareId,
          offset: offset,
          limit: limit + 1,
        );
        final items = <SoftwareProjection>[];
        for (final record in values.take(limit)) {
          final item = SoftwareEventView(record);
          if (!_fits([...items, item])) break;
          items.add(item);
        }
        return SoftwareValue(
          SoftwarePage(
            items,
            values.length > items.length
                ? _cursor(
                    'history',
                    profileId,
                    softwareId,
                    revision,
                    offset + items.length,
                  )
                : null,
          ),
        );
      }),
    ),
  );

  void _event(
    DomainTransaction r,
    Actor actor,
    SoftwareCardRecord card,
    String kind,
    List<String> changed,
  ) {
    final event = SoftwareEventRecord()
      ..eventId = _newId()
      ..profileId = card.profileId
      ..endpointId = card.endpointId
      ..host = card.host
      ..port = card.port
      ..username = card.username
      ..softwareId = card.softwareId
      ..softwareName = card.name
      ..kind = kind
      ..summary = kind
      ..changedFields = List.of(changed)
      ..createdAt = utcNow()
      ..actorKind = actor is McpActor ? 'mcp' : 'ui'
      ..clientId = actor is McpActor ? actor.clientId : null;
    SoftwareEventView(event);
    r.putSoftwareEvent(event);
  }

  Future<OperationResult<MutationValue>> _mutate(
    Actor actor,
    ReceiptMethod method,
    String mutationId,
    Map<String, Object?> payload,
    MutationValue Function(DomainTransaction) effect,
  ) {
    final future = () async {
      ReceiptTicket? ticket;
      try {
        ticket = receipts.ticket(actor, method, mutationId, payload);
        return await gate.submit(
          actor,
          (context) => repository.write((r) {
            _admit();
            final replay = receipts.lookup(context, r, ticket!);
            if (replay != null) return replay;
            return context.linearize(() {
              _admit();
              final result = effect(r);
              r.pruneSoftwareEvents(softwareEventLimit);
              final settings = r.settings
                ..dataRevision = nextRevision(r.settings.dataRevision)
                ..profilesListRevision = nextRevision(
                  r.settings.profilesListRevision,
                );
              r.putSettings(settings);
              receipts.record(r, ticket!, result, settings.dataRevision);
              return result;
            });
          }),
        );
      } catch (error) {
        return await gate.submit<MutationValue>(actor, (_) => throw error);
      } finally {
        ticket?.dispose();
        if (!_disposed) _notifier.value++;
      }
    }();
    final pending = future.then<void>((_) {});
    _pending.add(pending);
    pending.whenComplete(() => _pending.remove(pending));
    return future;
  }

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
  }

  @override
  Future<void> cancelPending() async {}
  @override
  Future<void> closeSessions() async {}
  @override
  Future<void> drain() async {
    await Future.wait(List.of(_pending));
  }

  @override
  Future<void> dispose() async {
    await stopAdmission();
    await drain();
    if (!_disposed) {
      _disposed = true;
      _notifier.dispose();
    }
  }
}
