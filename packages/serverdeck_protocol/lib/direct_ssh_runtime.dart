import 'package:cryptography/dart.dart';

import 'codec.dart';

/// Identity of the bundled local contract. It is not remote attestation or
/// authorization. Bump the descriptor revision when its semantics change.
abstract final class DirectSshRuntime {
  static const version = 'direct-ssh/1';
  static const environment = 'ubuntu24.04-amd64-systemd';
  static const _prerequisites = {
    'format': 1,
    'environment': environment,
    'transport': 'ssh-exec',
    'privilege': ['root', 'sudo-n'],
    'tools': ['sh', 'coreutils', 'flock', 'awk', 'systemctl', 'systemd-run'],
    'databaseTools': ['ss', 'runuser', 'psql', 'clickhouse-client'],
    'installTools': ['apt-get', 'apt-cache', 'dpkg-query', 'dpkg-deb', 'gpgv'],
  };
  static const _compiler = {
    'format': 1,
    'revision': 1,
    'effects': [
      'service_state',
      'service_enabled',
      'config_file',
      'database_configuration',
      'install_recipe',
    ],
    'configuration': 'fixed-renderers-v1-compound-database-activation',
    'dispatch': 'boot-uptime-permit-v1',
    'records': 'SDSSH1',
  };
  static const _registry = {
    'format': 1,
    'revision': 1,
    'environment': environment,
    'resources': {
      'system.motd': '/etc/motd',
      'postgresql.service': 'postgresql@16-main.service',
      'postgresql.settings': '/etc/postgresql/16/main/conf.d/serverdeck.conf',
      'clickhouse.service': 'clickhouse-server.service',
      'clickhouse.settings': '/etc/clickhouse-server/config.d/serverdeck.xml',
    },
    'recipes': ['postgresql16', 'clickhouse'],
    'ownership': 'verified-direct-step-resource-provenance-v1',
    'protectedPackages': ['netbird', 'netbird-*'],
  };

  static String _hash(Object value) => const DartSha256()
      .hashSync(StrictCodec().canonical(value))
      .bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  static final prerequisiteDigest = _hash(_prerequisites);
  static final compilerDigest = _hash(_compiler);
  static final registryDigest = _hash(_registry);

  static bool matches(Map<String, Object?> capsule) =>
      capsule['format'] == 2 &&
      capsule['environment'] == environment &&
      capsule['runtimeVersion'] == version &&
      capsule['runtimeLockDigest'] == prerequisiteDigest &&
      capsule['compilerDigest'] == compilerDigest &&
      capsule['registryDigest'] == registryDigest;
}
