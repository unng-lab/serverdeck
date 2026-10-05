import 'dart:convert';

typedef JsonMap = Map<String, dynamic>;
const localApiVersion = 1;
const catalog = {'postgresql': '18.6-3.pgdg24.04+1', 'clickhouse': '26.8.17.4'};

class LocalApiException implements Exception {
  const LocalApiException(this.code);
  final String code;
  @override
  String toString() => 'LocalApiException($code)';
}

final class JobPlan {
  JobPlan({
    required this.hostId,
    required this.hostFingerprint,
    required this.recipe,
    required this.version,
    required this.recipeDigest,
    required this.deviceId,
    this.mode = 'fresh',
  });
  final String hostId,
      hostFingerprint,
      recipe,
      version,
      recipeDigest,
      deviceId,
      mode;
  factory JobPlan.fromJson(JsonMap json) => JobPlan(
    hostId: json['hostId'] as String,
    hostFingerprint: json['hostFingerprint'] as String,
    recipe: json['recipe'] as String,
    version: json['version'] as String,
    recipeDigest: json['recipeDigest'] as String,
    deviceId: json['deviceId'] as String,
    mode: json['mode'] as String? ?? 'fresh',
  );
  JsonMap toJson() => {
    'hostId': hostId,
    'hostFingerprint': hostFingerprint,
    'recipe': recipe,
    'version': version,
    'recipeDigest': recipeDigest,
    'deviceId': deviceId,
    'mode': mode,
  };
  void validate() {
    if (![
          hostId,
          deviceId,
        ].every((v) => RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(v)) ||
        !catalog.containsKey(recipe) ||
        version != catalog[recipe] ||
        !RegExp(r'^sha256:[a-f0-9]{64}$').hasMatch(recipeDigest) ||
        !RegExp(r'^SHA256:[a-zA-Z0-9+/]{43}$').hasMatch(hostFingerprint) ||
        mode != 'fresh') {
      throw const LocalApiException('InvalidPlan');
    }
  }
}

final class ProbeEvidence {
  const ProbeEvidence({
    required this.version,
    required this.unitActive,
    required this.applicationHealthy,
    required this.executionStopped,
    required this.remoteLockClear,
  });
  final String version;
  final bool unitActive, applicationHealthy, executionStopped, remoteLockClear;
  JsonMap toJson() => {
    'version': version,
    'unitActive': unitActive,
    'applicationHealthy': applicationHealthy,
    'executionStopped': executionStopped,
    'remoteLockClear': remoteLockClear,
  };
}

// Fixed ordering binds exactly the reviewed input, never credentials or stdout.
String canonicalPlan(JobPlan plan) => jsonEncode(plan.toJson());

JsonMap validateProfile(JsonMap input) {
  const keys = {
    'id',
    'name',
    'endpoint',
    'port',
    'user',
    'tags',
    'state',
    'observedAt',
  };
  if (input.keys.any((key) => !keys.contains(key)) ||
      input['id'] is! String ||
      !RegExp(r'^[a-zA-Z0-9_-]{1,100}$').hasMatch(input['id'] as String) ||
      input['name'] is! String ||
      (input['name'] as String).trim().isEmpty ||
      (input['name'] as String).length > 200 ||
      input['endpoint'] is! String ||
      !RegExp(r'^[a-zA-Z0-9.-]+\.invalid$')
          .hasMatch(input['endpoint'] as String) ||
      input['port'] is! int ||
      input['port'] < 1 ||
      input['port'] > 65535 ||
      input['user'] is! String ||
      !RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(input['user'] as String) ||
      input['tags'] is! List ||
      (input['tags'] as List).length > 20 ||
      !(input['tags'] as List).every((v) => v is String && v.length <= 100) ||
      !['online', 'offline', 'unknown'].contains(input['state']) ||
      input['observedAt'] is! String ||
      DateTime.tryParse(input['observedAt'] as String) == null) {
    throw const LocalApiException('InvalidProfile');
  }
  if (utf8.encode(jsonEncode(input)).length > 4096) {
    throw const LocalApiException('InvalidProfile');
  }
  return Map<String, dynamic>.from(input);
}
