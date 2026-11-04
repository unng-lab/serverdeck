import '../runtime/owned_work.dart';

import 'dart:async';
import 'dart:convert';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/canonical_state.dart';
import '../domain/models.dart';
import '../domain/receipt_book.dart';
import '../runtime/capability.dart';
import '../storage/domain_repository.dart';
import '../storage/records.dart';
import 'credential_input.dart';

/// Private close-phase result. A replay performs no new invalidation/close.
final class ProfileCloseOutcome {
  const ProfileCloseOutcome.closed(VersionFence value)
    : fence = value,
      replay = null;
  const ProfileCloseOutcome.replayed(MutationValue value)
    : replay = value,
      fence = null;
  final VersionFence? fence;
  final MutationValue? replay;
}

/// Implemented by the canonical connection owner, never a permissive root stub.
abstract interface class ProfileConnectionPort
    implements ConnectionVersionState {
  ConnectionView connection(String profileId);
  TrustChallenge? challenge(String profileId);
  TrustView trustView(String profileId, EndpointTrust endpoint);
  bool isQuarantined(String endpointId);

  /// Invalidates generation under the common gate, closes outside it, then
  /// returns the current fence only on confirmed closure. Failure quarantines.
  /// When supplied, findReplay runs INSIDE the same authorized gate phase before
  /// entity/revision checks and invalidation, and again before post-close fences.
  Future<ProfileCloseOutcome> closeForMutation(
    Actor actor,
    String profileId,
    int expectedRevision, {
    MutationValue? Function(CommandContext context)? findReplay,
  });
}

final class ProfileOwner implements ProfileOperations, RuntimeCapability {
  ProfileOwner({
    required this.gate,
    required this.repository,
    required this.receipts,
    required this.credentials,
    required this.connections,
    required this.newId,
    required this.utcNow,
    this.onFailure,
  });
  final DomainCommandGate gate;
  final DomainRepository repository;
  final ReceiptBook receipts;
  final CredentialPreparer credentials;
  final ProfileConnectionPort connections;
  final String Function() newId;
  final int Function() utcNow;
  final void Function(Object, StackTrace)? onFailure;
  final Set<WorkCancellation> _tokens = {};
  final Set<Future<void>> _pending = {};
  bool _stopped = false;
  @override
  String get id => 'profiles';

  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor actor, {
    int limit = 50,
    String? cursor,
  }) => gate.submit(
    actor,
    (context) => context.read(
      () => repository.read((records) {
        if (limit < 1 || limit > 100)
          throw const OperationFailure(
            FailureCode.invalidArgument,
            field: OperationField.limit,
          );
        final revision = records.settings.profilesListRevision;
        _validRevision(revision);
        final all = records.profiles()..sort(_compareProfiles);
        (int, String)? after;
        if (cursor != null) {
          try {
            if (cursor.length > 1024) throw const FormatException();
            final decoded = jsonDecode(utf8.decode(base64Url.decode(cursor)));
            if (decoded is! List ||
                decoded.length != 3 ||
                decoded[0] is! int ||
                decoded[1] is! int ||
                decoded[2] is! String ||
                !isCanonicalUuid(decoded[2] as String))
              throw const FormatException();
            if (decoded[0] != revision)
              throw const OperationFailure(
                FailureCode.conflict,
                field: OperationField.cursor,
              );
            after = (decoded[1] as int, decoded[2] as String);
          } on OperationFailure {
            rethrow;
          } catch (_) {
            throw const OperationFailure(
              FailureCode.invalidArgument,
              field: OperationField.cursor,
            );
          }
        }
        final remaining = all
            .where(
              (p) =>
                  after == null ||
                  p.createdAt > after.$1 ||
                  (p.createdAt == after.$1 &&
                      p.profileId.compareTo(after.$2) > 0),
            )
            .toList();
        final page = remaining.take(limit).toList();
        return ProfilesPage(
          items: page.map((p) => _view(records, p)).toList(),
          snapshotRevision: revision,
          nextCursor: remaining.length <= limit
              ? null
              : base64Url.encode(
                  utf8.encode(
                    jsonEncode([
                      revision,
                      page.last.createdAt,
                      page.last.profileId,
                    ]),
                  ),
                ),
        );
      }),
    ),
  );

  @override
  Future<OperationResult<ProfileDetails>> getProfile(
    Actor actor,
    String profileId,
  ) => gate.submit(
    actor,
    (context) => context.read(
      () => repository.read((records) {
        final profile = _profile(records, profileId);
        final endpoint = _endpoint(records, profile.endpointId);
        return ProfileDetails(
          profile: _view(records, profile),
          connection: connections.connection(profileId),
          trust: connections.trustView(profileId, endpoint),
        );
      }),
    ),
  );

  @override
  Future<OperationResult<MutationValue>> createProfile(
    Actor actor,
    ProfileDraft draft, {
    required String mutationId,
  }) => _mutate(actor, draft.authentication, (cancellation) async {
    final ticket = receipts.ticket(
      actor,
      ReceiptMethod.createProfile,
      mutationId,
      {
        'profile': {
          'displayName': draft.displayName,
          'host': draft.host,
          if (draft.port != null) 'port': draft.port,
          'username': draft.username,
          'authentication': _authPayload(draft.authentication),
        },
      },
    );
    PreparedCredential? prepared;
    try {
      final replay = await gate.prepare<MutationValue?>(
        actor,
        (context) => repository.read(
          (records) => receipts.lookup(context, records, ticket),
        ),
      );
      if (replay != null) return await gate.submit(actor, (_) => replay);
      final fields = validateProfileFields(draft);
      _usable(fields.endpointId);
      final profileId = _newId(), credentialId = _newId();
      prepared = await credentials.prepare(
        draft.authentication,
        credentialId: credentialId,
        cancellation: cancellation,
      );
      cancellation.check();
      return await gate.submit(
        actor,
        (context) => repository.write((records) {
          final replay = receipts.lookup(context, records, ticket);
          if (replay != null) return replay;
          return context.linearize(() {
            _ensureAdmission();
            _usable(fields.endpointId);
            if (records.profiles().length >= 1000)
              throw const OperationFailure(FailureCode.resourceExhausted);
            if (records.profile(profileId) != null ||
                records.credential(credentialId) != null)
              throw const OperationFailure(FailureCode.conflict);
            final now = utcNow();
            final profile = Profile()
              ..profileId = profileId
              ..credentialId = credentialId
              ..createdAt = now
              ..updatedAt = now;
            _applyFields(profile, fields);
            profile.authKind = prepared!.kind.name;
            records.putCredential(
              _credential(credentialId, profileId, 1, prepared),
            );
            _addEndpoint(records, fields);
            records.putProfile(profile);
            final dataRevision = _advanceSettings(records);
            final result = MutationValue(entityId: profileId, revision: 1);
            receipts.record(records, ticket, result, dataRevision);
            return result;
          });
        }),
      );
    } catch (_) {
      // A matching concurrent request may have committed while this request was
      // preparing/closing. Resolve that committed outcome before reporting a
      // preparation failure; authorization still precedes the receipt lookup.
      final replay = await gate.prepare<MutationValue?>(
        actor,
        (context) => repository.read(
          (records) => receipts.lookup(context, records, ticket),
        ),
      );
      if (replay != null) return await gate.submit(actor, (_) => replay);
      rethrow;
    } finally {
      prepared?.dispose();
      ticket.dispose();
    }
  });

  @override
  Future<OperationResult<MutationValue>> updateProfile(
    Actor actor,
    String profileId,
    ProfilePatch patch, {
    required int expectedRevision,
    required String mutationId,
  }) => _mutate(actor, patch.authentication, (cancellation) async {
    final ticket = receipts.ticket(
      actor,
      ReceiptMethod.updateProfile,
      mutationId,
      {
        'profileId': profileId,
        'expectedRevision': expectedRevision,
        'patch': {
          if (patch.displayName != null) 'displayName': patch.displayName,
          if (patch.host != null) 'host': patch.host,
          if (patch.port != null) 'port': patch.port,
          if (patch.username != null) 'username': patch.username,
          if (patch.authentication != null)
            'authentication': _authPayload(patch.authentication!),
        },
      },
    );
    PreparedCredential? prepared;
    try {
      final intent = await gate.prepare<(MutationValue?, Profile?)>(
        actor,
        (context) => context.read(
          () => repository.read((records) {
            final replay = receipts.lookup(context, records, ticket);
            if (replay != null) return (replay, null);
            if (patch.isEmpty)
              throw const OperationFailure(
                FailureCode.invalidArgument,
                field: OperationField.request,
              );
            final current = _profile(records, profileId);
            _expected(current, expectedRevision);
            return (null, current);
          }),
        ),
      );
      if (intent.$1 != null) return await gate.submit(actor, (_) => intent.$1!);
      final old = intent.$2!;
      final fields = validateProfileValues(
        displayName: patch.displayName ?? old.displayName,
        host: patch.host ?? old.originalHost,
        port: patch.port ?? old.port,
        username: patch.username ?? old.username,
      );
      final connectionChange =
          fields.endpointId != old.endpointId ||
          fields.username != old.username ||
          patch.authentication != null;
      if (connectionChange) {
        _usable(old.endpointId);
        _usable(fields.endpointId);
      }
      String? credentialId;
      if (patch.authentication != null) {
        credentialId = _newId();
        prepared = await credentials.prepare(
          patch.authentication!,
          credentialId: credentialId,
          cancellation: cancellation,
        );
      }
      cancellation.check();
      VersionFence fence;
      if (connectionChange) {
        final outcome = await connections.closeForMutation(
          actor,
          profileId,
          expectedRevision,
          findReplay: (context) => repository.read(
            (records) => receipts.lookup(context, records, ticket),
          ),
        );
        if (outcome.replay != null)
          return await gate.submit(actor, (_) => outcome.replay!);
        fence =
            outcome.fence ??
            (throw const OperationFailure(FailureCode.storageUnavailable));
      } else {
        fence = VersionFence(
          profileId: profileId,
          profileRevision: expectedRevision,
          requiresUsableEndpoint: false,
        );
      }
      cancellation.check();
      return await gate.submit(
        actor,
        (context) => repository.write((records) {
          final replay = receipts.lookup(context, records, ticket);
          if (replay != null) return replay;
          return context.linearize(() {
            _ensureAdmission();
            final current = _profile(records, profileId);
            _expected(current, expectedRevision);
            if (connectionChange) {
              _usable(current.endpointId);
              _usable(fields.endpointId);
            }
            final currentCredential = _credentialRecord(records, current);
            if (fields.endpointId != current.endpointId) {
              _removeEndpoint(records, current.endpointId);
              _addEndpoint(records, fields);
            }
            if (prepared != null) {
              if (records.credential(credentialId!) != null)
                throw const OperationFailure(FailureCode.conflict);
              records.deleteCredential(current.credentialId);
              records.putCredential(
                _credential(
                  credentialId,
                  profileId,
                  nextRevision(currentCredential.secretRevision),
                  prepared,
                ),
              );
              current.credentialId = credentialId;
              current.authKind = prepared.kind.name;
            }
            _applyFields(current, fields);
            current.profileRevision = nextRevision(current.profileRevision);
            if (connectionChange)
              current.connectionRevision = nextRevision(
                current.connectionRevision,
              );
            current.updatedAt = utcNow();
            records.putProfile(current);
            final dataRevision = _advanceSettings(records);
            final result = MutationValue(
              entityId: profileId,
              revision: current.profileRevision,
            );
            receipts.record(records, ticket, result, dataRevision);
            return result;
          }, fence: fence);
        }),
      );
    } catch (_) {
      // A matching concurrent request may have committed while this request was
      // preparing/closing. Resolve that committed outcome before reporting a
      // preparation failure; authorization still precedes the receipt lookup.
      final replay = await gate.prepare<MutationValue?>(
        actor,
        (context) => repository.read(
          (records) => receipts.lookup(context, records, ticket),
        ),
      );
      if (replay != null) return await gate.submit(actor, (_) => replay);
      rethrow;
    } finally {
      prepared?.dispose();
      ticket.dispose();
    }
  });

  @override
  Future<OperationResult<MutationValue>> deleteProfile(
    UiActor actor,
    String profileId, {
    required int expectedRevision,
    required bool confirmed,
  }) => _mutate(actor, null, (cancellation) async {
    await gate.prepare<void>(
      actor,
      (context) => context.read(
        () => repository.read((records) {
          if (!confirmed)
            throw const OperationFailure(
              FailureCode.invalidArgument,
              field: OperationField.request,
            );
          final profile = _profile(records, profileId);
          _expected(profile, expectedRevision);
          _usable(profile.endpointId);
        }),
      ),
    );
    final outcome = await connections.closeForMutation(
      actor,
      profileId,
      expectedRevision,
    );
    final fence =
        outcome.fence ??
        (throw const OperationFailure(FailureCode.storageUnavailable));
    cancellation.check();
    return gate.submit(
      actor,
      (context) => repository.write(
        (records) => context.linearize(() {
          _ensureAdmission();
          final profile = _profile(records, profileId);
          _expected(profile, expectedRevision);
          _credentialRecord(records, profile);
          _usable(profile.endpointId);
          records.deleteProfile(profileId);
          records.deleteCredential(profile.credentialId);
          _removeEndpoint(records, profile.endpointId);
          _advanceSettings(records);
          return MutationValue(
            entityId: profileId,
            revision: profile.profileRevision,
          );
        }, fence: fence),
      ),
    );
  });

  Future<OperationResult<MutationValue>> _mutate(
    Actor actor,
    AuthenticationInput? input,
    Future<OperationResult<MutationValue>> Function(WorkCancellation) body,
  ) async {
    final cancellation = WorkCancellation();
    final done = Completer<void>();
    _tokens.add(cancellation);
    _pending.add(done.future);
    try {
      _ensureAdmission();
      return await body(cancellation);
    } catch (error, stack) {
      try {
        onFailure?.call(error, stack);
      } catch (_) {}
      final failure = error is OperationFailure
          ? error
          : error is WorkCancelled
          ? OperationFailure(
              _stopped ? FailureCode.shuttingDown : FailureCode.conflict,
            )
          : const OperationFailure(
              FailureCode.storageUnavailable,
              retryable: true,
            );
      return await gate.submit(actor, (_) => throw failure);
    } finally {
      input?.dispose();
      _tokens.remove(cancellation);
      _pending.remove(done.future);
      done.complete();
    }
  }

  void _ensureAdmission() {
    if (_stopped) throw const OperationFailure(FailureCode.shuttingDown);
  }

  void _usable(String endpointId) {
    if (connections.isQuarantined(endpointId))
      throw const OperationFailure(
        FailureCode.cleanupRequired,
        retryable: true,
        reason: FailureReason.connectionCleanup,
      );
  }

  String _newId() {
    final id = newId();
    if (!isCanonicalUuid(id))
      throw const OperationFailure(FailureCode.storageUnavailable);
    return id;
  }

  static void _validRevision(int n) {
    if (n < 1 || n > 9007199254740991)
      throw const OperationFailure(FailureCode.storageUnavailable);
  }

  static void _expected(Profile p, int revision) {
    if (revision < 1 || revision > 9007199254740991)
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.expectedRevision,
      );
    if (p.profileRevision != revision)
      throw const OperationFailure(
        FailureCode.conflict,
        field: OperationField.expectedRevision,
      );
  }

  static Profile _profile(DomainRead records, String id) {
    if (!isCanonicalUuid(id))
      throw const OperationFailure(
        FailureCode.invalidArgument,
        field: OperationField.profileId,
      );
    final p = records.profile(id);
    if (p == null) throw const OperationFailure(FailureCode.profileNotFound);
    _validRevision(p.profileRevision);
    _validRevision(p.connectionRevision);
    return p;
  }

  static Credential _credentialRecord(DomainRead records, Profile p) {
    final c = records.credential(p.credentialId);
    if (c == null ||
        c.profileId != p.profileId ||
        c.kind != p.authKind ||
        c.protectedBytes.isEmpty ||
        c.protectedBytes.length > 2 * 1024 * 1024)
      throw const OperationFailure(FailureCode.storageUnavailable);
    _validRevision(c.secretRevision);
    return c;
  }

  static EndpointTrust _endpoint(DomainRead records, String id) {
    final e = records.endpoint(id);
    if (e == null || e.profileRefCount < 1)
      throw const OperationFailure(FailureCode.storageUnavailable);
    _validRevision(e.trustRevision);
    _validRevision(e.observationRevision);
    return e;
  }

  static ProfileView _view(DomainRead records, Profile p) {
    _credentialRecord(records, p);
    _endpoint(records, p.endpointId);
    if (!isCanonicalUuid(p.profileId) ||
        !isCanonicalUuid(p.credentialId) ||
        !{'password', 'privateKey'}.contains(p.authKind))
      throw const OperationFailure(FailureCode.storageUnavailable);
    _validRevision(p.profileRevision);
    _validRevision(p.connectionRevision);
    return ProfileView(
      profileId: p.profileId,
      revision: p.profileRevision,
      connectionRevision: p.connectionRevision,
      displayName: p.displayName,
      host: p.originalHost,
      port: p.port,
      username: p.username,
      authKind: p.authKind == 'password'
          ? AuthKind.password
          : AuthKind.privateKey,
      hasCredential: true,
      endpointId: p.endpointId,
    );
  }

  static Credential _credential(
    String id,
    String profileId,
    int revision,
    PreparedCredential prepared,
  ) => Credential()
    ..credentialId = id
    ..profileId = profileId
    ..kind = prepared.kind.name
    ..secretRevision = revision
    ..protectedBytes = prepared.ciphertext.toList()
    ..publicKeyType = prepared.inspection?.keyType
    ..publicKeyBytes = prepared.inspection?.publicKeyBytes.toList()
    ..publicKeyBits = prepared.inspection?.bits;
  static void _applyFields(Profile p, ValidatedProfileFields f) {
    p.displayName = f.displayName;
    p.originalHost = f.originalHost;
    p.normalizedHost = f.normalizedHost;
    p.port = f.port;
    p.username = f.username;
    p.endpointId = f.endpointId;
  }

  static void _addEndpoint(
    DomainTransaction records,
    ValidatedProfileFields f,
  ) {
    final existing = records.endpoint(f.endpointId);
    final e =
        existing ??
        (EndpointTrust()
          ..endpointId = f.endpointId
          ..normalizedHost = f.normalizedHost
          ..port = f.port);
    if (e.normalizedHost != f.normalizedHost ||
        e.port != f.port ||
        e.profileRefCount < 0 ||
        (existing != null && e.profileRefCount == 0) ||
        e.profileRefCount >= 1000)
      throw const OperationFailure(FailureCode.storageUnavailable);
    e.profileRefCount++;
    records.putEndpoint(e);
  }

  static void _removeEndpoint(DomainTransaction records, String id) {
    final e = _endpoint(records, id);
    if (e.profileRefCount == 1) {
      records.deleteEndpoint(id);
    } else {
      e.profileRefCount--;
      records.putEndpoint(e);
    }
  }

  static int _advanceSettings(DomainTransaction records) {
    final settings = records.settings;
    settings.dataRevision = nextRevision(settings.dataRevision);
    settings.profilesListRevision = nextRevision(settings.profilesListRevision);
    records.putSettings(settings);
    return settings.dataRevision;
  }

  static int _compareProfiles(Profile a, Profile b) {
    final time = a.createdAt.compareTo(b.createdAt);
    return time != 0 ? time : a.profileId.compareTo(b.profileId);
  }

  static Map<String, Object?> _authPayload(AuthenticationInput input) =>
      switch (input) {
        PasswordInput() => {'kind': 'password', 'password': input.password},
        PrivateKeyInput() => {
          'kind': 'privateKey',
          'keyBase64': base64.encode(input.bytes),
          if (input.passphrase != null) 'passphrase': input.passphrase,
        },
      };

  @override
  Future<void> stopAdmission() async {
    _stopped = true;
  }

  @override
  Future<void> cancelPending() async {
    for (final token in List.of(_tokens)) {
      token.cancel();
    }
  }

  @override
  Future<void> closeSessions() => drain();
  @override
  Future<void> drain() => Future.wait(List.of(_pending));
  @override
  Future<void> dispose() async {
    await stopAdmission();
    await cancelPending();
    await drain();
  }
}
