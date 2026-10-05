import 'package:flutter/material.dart';
import 'package:serverdeck_locald/local_api.dart';

import 'data/fixtures.dart';
import 'data/local_profiles.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocalApiClient? client;
  try {
    client = await ensureLocald();
    await client.initializeProfiles(
      FixtureRepository().servers.map(profileJson).toList(),
    );
    final profiles = (await client.profiles()).map(profileFromJson).toList();
    if (profiles.isEmpty) {
      throw const LocalApiException('ProfilesUnavailable');
    }
    runApp(ServerDeckApp(client: client, profiles: profiles));
  } catch (_) {
    client?.close();
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Локальное хранилище недоступно.\nПроверьте наличие serverdeck_locald.exe и libisar.dll\n'
              'рядом с приложением и перезапустите ServerDeck.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
