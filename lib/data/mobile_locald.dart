import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:serverdeck_locald/local_api.dart';
import 'package:serverdeck_locald/locald.dart';

/// Android owns the service inside its application sandbox and process.
class MobileLocald {
  MobileLocald._(this.server, this.client);
  final LocaldServer server;
  final LocalApiClient client;
  static Future<MobileLocald> start() async {
    final directory = await getApplicationSupportDirectory();
    final server = await LocaldServer.start(
      directory: p.join(directory.path, 'ServerDeck', 'workspace'),
      nativeLibraryPath: 'libisar.so',
    );
    final client = LocalApiClient(port: server.port, proof: server.proof);
    await client.health();
    return MobileLocald._(server, client);
  }

  Future<void> close() async {
    client.close();
    await server.close();
  }
}
