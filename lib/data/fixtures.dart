import '../domain/models.dart';

/// Entirely synthetic; no network, real inventory or copied Logs source.
class FixtureRepository {
  FixtureRepository({DateTime? now, List<ServerProfile>? profiles})
    : createdAt = now ?? DateTime.now().toUtc() {
    servers = profiles == null
        ? [
            ServerProfile(
              id: 'lab-a',
              name: 'Ubuntu Lab',
              endpoint: 'ubuntu-lab.invalid',
              tags: ['lab', 'Ubuntu 24.04'],
              observedAt: createdAt,
            ),
            ServerProfile(
              id: 'lab-b',
              name: 'Analytics Lab',
              endpoint: 'analytics-lab.invalid',
              tags: ['lab', 'ClickHouse'],
              observedAt: createdAt.subtract(const Duration(minutes: 8)),
              state: 'offline',
            ),
            ServerProfile(
              id: 'lab-c',
              name: 'New fixture',
              endpoint: 'new-lab.invalid',
              tags: ['не проверен'],
              observedAt: createdAt,
              state: 'unknown',
            ),
          ]
        : List.of(profiles);
    for (final server in servers) {
      sessions[server.id] = JournalSession();
    }
    for (final id in ['lab-a', 'lab-b']) {
      if (sessions.containsKey(id)) {
        loadHistory(id, 100);
      }
    }
  }
  final DateTime createdAt;
  late final List<ServerProfile> servers;
  final Map<String, JournalSession> sessions = {};
  int _sequence = 0;
  static const software = [
    Software(
      serverId: 'lab-a',
      name: 'PostgreSQL',
      version: '18.6',
      source: 'dpkg',
      unit: 'postgresql@18-main.service',
      state: 'active',
    ),
    Software(
      serverId: 'lab-a',
      name: 'Nginx',
      version: '1.24.0',
      source: 'dpkg',
      unit: 'nginx.service',
      state: 'inactive',
    ),
    Software(
      serverId: 'lab-a',
      name: 'Worker',
      source: 'systemd unit',
      unit: 'worker@batch.service',
      state: 'failed',
      confidence: 'версия неизвестна',
    ),
    Software(
      serverId: 'lab-b',
      name: 'ClickHouse',
      version: '26.8.17.4',
      source: 'dpkg',
      unit: 'clickhouse-server.service',
      state: 'unknown',
      confidence: 'последнее наблюдение; нет связи',
    ),
    Software(
      serverId: 'lab-b',
      name: 'Custom exporter',
      source: 'binary',
      unit: 'exporter.service',
      state: 'unknown',
      confidence: 'детектор версии недоступен',
    ),
  ];
  List<Software> installed(String serverId) =>
      software.where((s) => s.serverId == serverId).toList();
  HostMetrics metrics(ServerProfile server) {
    final unavailable = server.state == 'unknown';
    Observation<double> metric(double value) => Observation(
      value: unavailable ? null : value,
      observedAt: server.observedAt,
      status: unavailable
          ? ObservationStatus.unknown
          : ObservationStatus.available,
    );
    return HostMetrics(
      cpu: metric(23.4),
      ram: metric(5.2),
      disk: metric(38.6),
      network: Observation(
        value: null,
        observedAt: server.observedAt,
        status: ObservationStatus.unsupported,
      ),
      uptime: unavailable ? null : '4 д 12 ч',
    );
  }

  void loadHistory(String serverId, int limit) {
    validateHistoryLimit(limit);
    final session = sessions[serverId]!;
    session.historyLimit = limit;
    for (var i = 0; i < limit; i++) {
      final unit = serverId == 'lab-b'
          ? 'clickhouse-server.service'
          : i % 9 == 0
          ? 'worker@batch.service'
          : 'postgresql@18-main.service';
      session.journal.add(
        JournalRecord(
          cursor: 'history-$i',
          bootId: 'demo-boot-$serverId',
          at: createdAt.subtract(Duration(seconds: (limit - i) * 3)),
          unit: unit,
          priority: i % 9 == 0 ? 3 : 6,
          message: i % 9 == 0
              ? 'worker exited with status 1 — synthetic event'
              : i % 3 == 0
              ? 'checkpoint complete: wrote 24 buffers — synthetic event'
              : 'Started PostgreSQL fixture observation $i',
          fields: {'_HOSTNAME': 'fixture.invalid', 'SYSLOG_IDENTIFIER': 'demo'},
        ),
      );
    }
  }

  void appendEvent(String serverId) {
    sessions[serverId]!.journal.add(
      JournalRecord(
        cursor: 'live-${_sequence++}',
        bootId: 'demo-boot-$serverId',
        at: DateTime.now().toUtc(),
        unit: serverId == 'lab-b'
            ? 'clickhouse-server.service'
            : 'postgresql@18-main.service',
        priority: 6,
        message: 'checkpoint complete — synthetic live event $_sequence',
      ),
    );
  }

  void add(ServerProfile server) {
    servers.add(server);
    sessions[server.id] = JournalSession();
  }

  void remove(String id) {
    servers.removeWhere((s) => s.id == id);
    sessions.remove(id);
  }
}
