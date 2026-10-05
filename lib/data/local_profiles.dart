import 'package:serverdeck_locald/local_api.dart';

import '../domain/models.dart';

JsonMap profileJson(ServerProfile p) => {
  'id': p.id,
  'name': p.name,
  'endpoint': p.endpoint,
  'port': p.port,
  'user': p.user,
  'tags': p.tags,
  'state': p.state,
  'observedAt': p.observedAt.toUtc().toIso8601String(),
};
ServerProfile profileFromJson(JsonMap p) => ServerProfile(
  id: p['id'] as String,
  name: p['name'] as String,
  endpoint: p['endpoint'] as String,
  port: p['port'] as int,
  user: p['user'] as String,
  tags: (p['tags'] as List).cast<String>(),
  state: p['state'] as String,
  observedAt: DateTime.parse(p['observedAt'] as String),
);
