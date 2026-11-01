import 'package:path/path.dart' as p;
import 'package:serverdeck_engine/platform/publication_identity.dart';

/// Windows spelling policy, kept pure so adapter identity can be unit-tested
/// without importing/loading any native library. This is not a peer proof.
PublicationIdentity windowsPublicationIdentity({
  required String ownerIdentity,
  required String appRoot,
  required String generation,
}) {
  final windows = p.Context(style: p.Style.windows);
  if (appRoot.length > 32767 || !windows.isAbsolute(appRoot)) {
    throw StateError('UNAUTHORIZED');
  }
  return PublicationIdentity(
    ownerIdentity: ownerIdentity,
    appRoot: windows.normalize(appRoot).toLowerCase(),
    generation: generation,
  );
}
