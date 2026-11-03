import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/actor.dart';
import '../domain/app_operations.dart';
import '../domain/models.dart';

/// C02/C10/C11 actions share the same typed API as MCP; no widget owns authority.
final class ProfileController extends ChangeNotifier {
  ProfileController({
    required this.operations,
    required this.actor,
    required this.newId,
    Stream<void>? changes,
    bool poll = true,
  }) {
    _subscription = changes?.listen((_) => unawaited(refresh()));
    if (poll)
      _timer = Timer.periodic(
        const Duration(seconds: 1),
        (_) => unawaited(refresh()),
      );
  }
  final AppOperations operations;
  final UiActor actor;
  final String Function() newId;
  List<ProfileView> items = [];
  ProfileDetails? details;
  OperationFailure? error;
  Map<String, TrustView> trusts = {};
  String? selected;
  bool loading = false, pending = false, _disposed = false;
  int _selection = 0;
  StreamSubscription<void>? _subscription;
  Timer? _timer;
  Future<void>? _refresh;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() =>
      _refresh ??= _load().whenComplete(() => _refresh = null);
  Future<void> _load() async {
    if (_disposed) return;
    loading = items.isEmpty;
    _notify();
    try {
      final values = <ProfileView>[];
      String? cursor;
      do {
        final result = await operations.listProfiles(
          actor,
          limit: 100,
          cursor: cursor,
        );
        if (result.error != null) throw result.error!;
        values.addAll(result.value!.items);
        cursor = result.value!.nextCursor;
      } while (cursor != null && !_disposed);
      if (_disposed) return;
      items = List.unmodifiable(values);
      final nextTrusts = <String, TrustView>{};
      for (final profile in values) {
        if (_disposed) return;
        final result = await operations.getTrust(actor, profile.profileId);
        if (result.value != null)
          nextTrusts[profile.profileId] = result.value!;
        else if (trusts.containsKey(profile.profileId))
          nextTrusts[profile.profileId] = trusts[profile.profileId]!;
      }
      if (_disposed) return;
      trusts = Map.unmodifiable(nextTrusts);
      final id = selected, selection = _selection;
      if (id != null) {
        final result = await operations.getProfile(actor, id);
        if (_disposed || selection != _selection) return;
        if (result.error?.code == FailureCode.profileNotFound) {
          selected = null;
          details = null;
        } else if (result.error != null)
          throw result.error!;
        else
          details = result.value;
      }
      error = null;
    } on OperationFailure catch (e) {
      if (!_disposed) error = e;
    } catch (_) {
      if (!_disposed)
        error = const OperationFailure(FailureCode.storageUnavailable);
    } finally {
      loading = false;
      _notify();
    }
  }

  Future<void> select(String? id) async {
    selected = id;
    details = null;
    _selection++;
    _notify();
    await refresh();
    if (selected == id && details == null && id != null) await refresh();
  }

  Future<OperationFailure?> _action<T extends PublicValue>(
    Future<OperationResult<T>> Function() action,
  ) async {
    if (pending) return const OperationFailure(FailureCode.conflict);
    pending = true;
    _notify();
    OperationFailure? failure;
    try {
      final result = await action();
      failure = result.error;
    } on OperationFailure catch (e) {
      failure = e;
    } catch (_) {
      failure = const OperationFailure(FailureCode.storageUnavailable);
    } finally {
      pending = false;
      if (!_disposed) {
        await refresh();
        error = failure;
        _notify();
      }
    }
    return failure;
  }

  Future<OperationFailure?> create(ProfileDraft draft, String mutationId) =>
      _action(
        () => operations.createProfile(actor, draft, mutationId: mutationId),
      );
  Future<OperationFailure?> update(
    ProfileView profile,
    ProfilePatch patch,
    String mutationId,
  ) => _action(
    () => operations.updateProfile(
      actor,
      profile.profileId,
      patch,
      expectedRevision: profile.revision,
      mutationId: mutationId,
    ),
  );
  Future<OperationFailure?> delete(
    ProfileView profile, {
    required bool confirmed,
  }) => _action(
    () => operations.deleteProfile(
      actor,
      profile.profileId,
      expectedRevision: profile.revision,
      confirmed: confirmed,
    ),
  );
  Future<OperationFailure?> connect(ProfileView profile) => _action(
    () => operations.connect(
      actor,
      profile.profileId,
      expectedRevision: profile.revision,
    ),
  );
  Future<OperationFailure?> cancel(String id, String attemptId) => _action(
    () => operations.cancelConnection(actor, id, attemptId: attemptId),
  );
  Future<OperationFailure?> disconnect(String id, String sessionId) =>
      _action(() => operations.disconnect(actor, id, sessionId: sessionId));
  Future<OperationFailure?> providePassphrase(
    String id,
    PendingInput input,
    String passphrase,
  ) => _action(
    () => operations.providePassphrase(
      actor,
      id,
      attemptId: input.attemptId,
      nonce: input.nonce,
      passphrase: passphrase,
    ),
  );
  Future<OperationFailure?> decide(
    String id,
    TrustChallenge c, {
    required bool confirmed,
    required String mutationId,
  }) => _action(
    () => switch (c.kind) {
      TrustKind.first => operations.acceptTrust(
        actor,
        TrustDecision(
          profileId: id,
          attemptId: c.attemptId,
          nonce: c.nonce,
          expectedProfileRevision: c.profileRevision,
          expectedTrustRevision: c.trustRevision,
          expectedObservationRevision: c.observationRevision,
          fingerprint: c.fingerprint,
          mutationId: mutationId,
          confirmed: confirmed,
        ),
      ),
      TrustKind.replace => operations.replaceTrust(
        actor,
        ReplacementDecision(
          profileId: id,
          attemptId: c.attemptId,
          nonce: c.nonce,
          expectedProfileRevision: c.profileRevision,
          expectedTrustRevision: c.trustRevision,
          expectedObservationRevision: c.observationRevision,
          fingerprint: c.fingerprint,
          oldFingerprint: c.oldFingerprint!,
          newFingerprint: c.fingerprint,
          mutationId: mutationId,
          confirmed: confirmed,
        ),
      ),
      TrustKind.retain => operations.retainTrust(
        actor,
        RetentionDecision(
          profileId: id,
          attemptId: c.attemptId,
          nonce: c.nonce,
          expectedProfileRevision: c.profileRevision,
          expectedTrustRevision: c.trustRevision,
          expectedObservationRevision: c.observationRevision,
          fingerprint: c.fingerprint,
          acceptedFingerprint: c.fingerprint,
          mutationId: mutationId,
          confirmed: confirmed,
        ),
      ),
    },
  );
  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
