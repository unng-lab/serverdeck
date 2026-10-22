part of 'operational_auth_client.dart';

/// Private adapters capture actual typed native peers. Public constructors
/// cannot supply these callbacks or convert a format2 session into format3.
final class _ClientPeer {
  _ClientPeer._(
    this.role,
    this.localRole,
    this.buildId,
    this.revalidate,
    this._read,
    this._write,
  );
  factory _ClientPeer.operational(OperationalPipePeer peer) => _ClientPeer._(
    peer.role,
    peer.localRole,
    peer.buildId,
    peer.revalidate,
    (count, deadline) => peer.read(count: count, deadline: deadline),
    (bytes, deadline) => peer.write(bytes, deadline: deadline),
  );
  factory _ClientPeer.trusted(TrustedPipePeer peer) => _ClientPeer._(
    peer.role,
    peer.localRole,
    peer.buildId,
    peer.revalidate,
    (count, deadline) => peer.read(count: count, deadline: deadline),
    (bytes, deadline) => peer.write(bytes, deadline: deadline),
  );
  final BundlePeerRole role, localRole;
  final String buildId;
  final Future<void> Function() revalidate;
  final Future<Uint8List> Function(int, Duration) _read;
  final Future<void> Function(List<int>, Duration) _write;
  Future<Uint8List> read({required int count, required Duration deadline}) =>
      _read(count, deadline);
  Future<void> write(List<int> bytes, {required Duration deadline}) =>
      _write(bytes, deadline);
}
