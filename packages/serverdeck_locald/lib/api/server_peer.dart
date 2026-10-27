part of 'operational_auth.dart';

/// Private adapters capture actual native2/3 proofs. No public callback or
/// schema/role flag can mint a peer or turn one format into the other.
final class _ServerPeer {
  _ServerPeer._(
    this.localRole,
    this.role,
    this.buildId,
    NativeProofDelegate revalidate,
    Future<String> Function() verifiedBundleRoot,
  ) : _control = NativeControlQueue(
        revalidate: revalidate,
        verifiedBundleRoot: verifiedBundleRoot,
      );
  factory _ServerPeer.operational(OperationalPipePeer peer) => _ServerPeer._(
    peer.localRole,
    peer.role,
    peer.buildId,
    peer.revalidate,
    peer.verifiedBundleRoot,
  );
  factory _ServerPeer.trusted(TrustedPipePeer peer) => _ServerPeer._(
    peer.localRole,
    peer.role,
    peer.buildId,
    peer.revalidate,
    peer.verifiedBundleRoot,
  );
  final BundlePeerRole localRole, role;
  final String buildId;
  final NativeControlQueue _control;

  NativeControlTicket<void> beginRevalidation({
    required Duration Function() remaining,
    List<NativeControlScope> scopes = const [],
    void Function(Future<void>)? observeNativeCompletion,
  }) => _control.proof(
    remaining: remaining,
    scopes: scopes,
    observeNativeCompletion: observeNativeCompletion,
  );

  Future<void> revalidate({
    required Duration Function() remaining,
    List<NativeControlScope> scopes = const [],
    void Function(Future<void>)? observeNativeCompletion,
  }) => beginRevalidation(
    remaining: remaining,
    scopes: scopes,
    observeNativeCompletion: observeNativeCompletion,
  ).result;

  Future<String> verifiedBundleRoot({
    required Duration Function() remaining,
    List<NativeControlScope> scopes = const [],
  }) => _control.bundleRoot(remaining: remaining, scopes: scopes).result;

  void bindFailureHandler(void Function() handler) =>
      _control.bindFailureHandler(handler);
  void retire() => _control.retire();
  Future<void> get settled => _control.settled;
}
