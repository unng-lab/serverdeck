import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:serverdeck_locald/local_api.dart';

import 'data/fixtures.dart';
import 'data/app_updates.dart';
import 'data/mobile_locald.dart';
import 'data/rustore_updates.dart';
import 'data/local_profiles.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LocalApiClient? client;
  try {
    client = Platform.isAndroid
        ? (await MobileLocald.start()).client
        : await ensureLocald();
    await client.initializeProfiles(
      FixtureRepository().servers.map(profileJson).toList(),
    );
    final profiles = (await client.profiles()).map(profileFromJson).toList();
    if (profiles.isEmpty) {
      throw const LocalApiException('ProfilesUnavailable');
    }
    final package = await PackageInfo.fromPlatform();
    final version = '${package.version}+${package.buildNumber}';
    final localClient = client;
    final updater = Platform.isAndroid
        ? RuStoreUpdater(
            installedVersion: version,
            installedBuild: int.parse(package.buildNumber),
            packageName: package.packageName,
          )
        : AppUpdater(
            version: version,
            platform: desktopPlatformKey(),
            opener: (file) async {
              await localClient.call('service/stop');
              await Future<void>.delayed(const Duration(milliseconds: 500));
              await AppUpdater.openPackage(file);
            },
          );
    runApp(ServerDeckApp(client: client, profiles: profiles, updater: updater));
  } catch (_) {
    client?.close();
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Локальное хранилище недоступно.\nПерезапустите ServerDeck.\n'
              'На компьютере проверьте полноту установленного пакета приложения.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
