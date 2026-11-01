import 'package:serverdeck_engine/hosting/capability_snapshot.dart';
import 'package:serverdeck_engine/platform/ports.dart';
import 'package:test/test.dart';

EngineCapabilities ready({Iterable<String> reasons = const []}) =>
    EngineCapabilities(
      platform: EnginePlatformKind.windows,
      storageReady: true,
      vaultStatus: VaultAccess.available,
      directSsh: true,
      localMcpBridge: true,
      trayAvailable: false,
      backgroundPolicy: EngineBackgroundPolicy.desktopWhileRunning,
      reasonCodes: reasons,
    );

void main() {
  for (final platform in EnginePlatformKind.values) {
    test('explicit current platform row ${platform.name}', () {
      final caps = EngineCapabilities.unavailable(platform);
      expect(caps.platform, platform);
      expect(caps.coreUsable, isFalse);
      expect(
        caps.storageReady ||
            caps.directSsh ||
            caps.localMcpBridge ||
            caps.trayAvailable,
        isFalse,
      );
      expect(caps.vaultStatus, VaultAccess.unavailable);
      expect(caps.backgroundPolicy, switch (platform) {
        EnginePlatformKind.windows =>
          EngineBackgroundPolicy.desktopWhileRunning,
        EnginePlatformKind.android ||
        EnginePlatformKind.ios => EngineBackgroundPolicy.foregroundOnly,
        _ => EngineBackgroundPolicy.unsupported,
      });
      expect(caps.reasonCodes, [
        platform == EnginePlatformKind.windows
            ? 'NOT_READY'
            : 'PREREQUISITE_UNAVAILABLE',
      ]);
      expect(
        EngineCapabilities.fromJson(caps.toJson()).toJson(),
        caps.toJson(),
      );
      if (platform != EnginePlatformKind.windows) {
        expect(() => caps.withTray(true), throwsFormatException);
        for (final field in [
          'storageReady',
          'directSsh',
          'localMcpBridge',
          'trayAvailable',
        ]) {
          expect(
            () => EngineCapabilities.fromJson({...caps.toJson(), field: true}),
            throwsFormatException,
          );
        }
      }
    });
  }
  test(
    'ready and tray copy are immutable availability, withdrawal clears proof',
    () {
      final caps = ready(), tray = ready().withTray(true);
      expect(caps.coreUsable, isTrue);
      expect(caps.trayAvailable, isFalse);
      expect(tray.trayAvailable, isTrue);
      final map = tray.toJson();
      (map['reasonCodes'] as List).add('TIMEOUT');
      expect(tray.reasonCodes, isEmpty);
      expect(() => tray.reasonCodes.add('TIMEOUT'), throwsUnsupportedError);
      final withdrawn = tray.withdraw('NOT_READY');
      expect(
        withdrawn.coreUsable || withdrawn.directSsh || withdrawn.localMcpBridge,
        isFalse,
      );
      expect(withdrawn.vaultStatus, VaultAccess.unavailable);
      expect(withdrawn.trayAvailable, isTrue);
      expect(tray.coreUsable, isTrue);
    },
  );
  test(
    'closed parser rejects type, shape, ordering and contradictory claims',
    () {
      final good = ready().toJson();
      for (final key in good.keys) {
        final missing = Map<String, Object?>.of(good)..remove(key);
        expect(
          () => EngineCapabilities.fromJson(missing),
          throwsFormatException,
        );
        expect(
          () => EngineCapabilities.fromJson({...good, key: null}),
          throwsFormatException,
        );
      }
      for (final bad in [
        {...good, 'role': 'owner'},
        {...good, 'platform': 'future'},
        {...good, 'storageReady': 1},
        {...good, 'vaultStatus': 'unknown'},
        {
          ...good,
          'reasonCodes': ['NOT_READY'],
        },
        {...good, 'backgroundPolicy': 'foregroundOnly'},
        {
          ...EngineCapabilities.unavailable(EnginePlatformKind.windows)
              .toJson(),
          'reasonCodes': ['TIMEOUT', 'NOT_READY'],
        },
        {
          ...EngineCapabilities.unavailable(EnginePlatformKind.windows)
              .toJson(),
          'reasonCodes': ['NOT_READY', 'NOT_READY'],
        },
        {
          ...EngineCapabilities.unavailable(EnginePlatformKind.windows)
              .toJson(),
          'reasonCodes': List.filled(9, 'NOT_READY'),
        },
        {
          ...EngineCapabilities.unavailable(EnginePlatformKind.windows)
              .toJson(),
          'reasonCodes': ['PRIVATE_DETAIL'],
        },
      ]) {
        expect(() => EngineCapabilities.fromJson(bad), throwsFormatException);
      }
    },
  );
  test(
    'negative vault and copied canonical reasons cannot manufacture success',
    () {
      final reasons = ['STORAGE_BLOCKED', 'NOT_READY', 'NOT_READY'];
      final caps = EngineCapabilities(
        platform: EnginePlatformKind.windows,
        storageReady: false,
        vaultStatus: VaultAccess.locked,
        directSsh: false,
        localMcpBridge: false,
        trayAvailable: false,
        backgroundPolicy: EngineBackgroundPolicy.desktopWhileRunning,
        reasonCodes: reasons,
      );
      reasons.clear();
      expect(caps.reasonCodes, ['NOT_READY', 'STORAGE_BLOCKED']);
      expect(caps.coreUsable, isFalse);
      expect(
        EngineCapabilities.unavailable(
          EnginePlatformKind.windows,
          reason: 'private',
        ).reasonCodes,
        ['SERVICE_UNAVAILABLE'],
      );
    },
  );
}
