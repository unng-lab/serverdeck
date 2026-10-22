part of 'operational_auth.dart';

/// Private adapters capture actual native2/3 proofs. No public callback or
/// schema/role flag can mint a peer or turn one format into the other.
final class _ServerPeer {
  _ServerPeer._(this.localRole, this.role, this.buildId, this._revalidate);
  factory _ServerPeer.operational(OperationalPipePeer peer) =>
      _ServerPeer._(peer.localRole, peer.role, peer.buildId, peer.revalidate);
  factory _ServerPeer.trusted(TrustedPipePeer peer) =>
      _ServerPeer._(peer.localRole, peer.role, peer.buildId, peer.revalidate);
  final BundlePeerRole localRole, role;
  final String buildId;
  final Future<void> Function({
    void Function(Future<void>)? observeNativeCompletion,
  })
  _revalidate;
  Future<void> revalidate({
    void Function(Future<void>)? observeNativeCompletion,
  }) => _revalidate(observeNativeCompletion: observeNativeCompletion);
}
