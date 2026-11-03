import 'actor.dart';
import 'app_operations.dart';
import 'models.dart';

/// The sole public facade; each owner retains its canonical admission boundary.
final class OwnedAppOperations implements AppOperations {
  const OwnedAppOperations(this.profiles, this.connections, this.trust);
  final ProfileOperations profiles;
  final ConnectionOperations connections;
  final TrustOperations trust;
  @override
  Future<OperationResult<ProfilesPage>> listProfiles(
    Actor a, {
    int limit = 50,
    String? cursor,
  }) => profiles.listProfiles(a, limit: limit, cursor: cursor);
  @override
  Future<OperationResult<ProfileDetails>> getProfile(Actor a, String id) =>
      profiles.getProfile(a, id);
  @override
  Future<OperationResult<MutationValue>> createProfile(
    Actor a,
    ProfileDraft d, {
    required String mutationId,
  }) => profiles.createProfile(a, d, mutationId: mutationId);
  @override
  Future<OperationResult<MutationValue>> updateProfile(
    Actor a,
    String id,
    ProfilePatch p, {
    required int expectedRevision,
    required String mutationId,
  }) => profiles.updateProfile(
    a,
    id,
    p,
    expectedRevision: expectedRevision,
    mutationId: mutationId,
  );
  @override
  Future<OperationResult<MutationValue>> deleteProfile(
    UiActor a,
    String id, {
    required int expectedRevision,
    required bool confirmed,
  }) => profiles.deleteProfile(
    a,
    id,
    expectedRevision: expectedRevision,
    confirmed: confirmed,
  );
  @override
  Future<OperationResult<ConnectionView>> connect(
    Actor a,
    String id, {
    required int expectedRevision,
  }) => connections.connect(a, id, expectedRevision: expectedRevision);
  @override
  Future<OperationResult<ConnectionView>> getConnection(Actor a, String id) =>
      connections.getConnection(a, id);
  @override
  Future<OperationResult<ConnectionView>> providePassphrase(
    Actor a,
    String id, {
    required String attemptId,
    required String nonce,
    required String passphrase,
  }) => connections.providePassphrase(
    a,
    id,
    attemptId: attemptId,
    nonce: nonce,
    passphrase: passphrase,
  );
  @override
  Future<OperationResult<ConnectionView>> cancelConnection(
    Actor a,
    String id, {
    required String attemptId,
  }) => connections.cancelConnection(a, id, attemptId: attemptId);
  @override
  Future<OperationResult<ConnectionView>> disconnect(
    Actor a,
    String id, {
    required String sessionId,
  }) => connections.disconnect(a, id, sessionId: sessionId);
  @override
  Future<OperationResult<TrustView>> getTrust(Actor a, String id) =>
      trust.getTrust(a, id);
  @override
  Future<OperationResult<MutationValue>> acceptTrust(
    Actor a,
    TrustDecision d,
  ) => trust.acceptTrust(a, d);
  @override
  Future<OperationResult<MutationValue>> replaceTrust(
    Actor a,
    ReplacementDecision d,
  ) => trust.replaceTrust(a, d);
  @override
  Future<OperationResult<MutationValue>> retainTrust(
    Actor a,
    RetentionDecision d,
  ) => trust.retainTrust(a, d);
}
