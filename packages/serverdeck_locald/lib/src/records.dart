import 'package:isar_community/isar.dart';

part 'records.g.dart';

@collection
class ProfileRecord {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  late String profileId;
  late String payload;
}

@collection
class JobRecord {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  late String jobId;
  @Index(unique: true)
  late String idempotencyKey;
  late String inputJson;
  late String inputHash;
  late String fingerprint;
  late String phase;
  String? containerId;
  late DateTime createdAt;
  int sequence = 0;
}

@collection
class HostLockRecord {
  Id id = Isar.autoIncrement;
  @Index(unique: true)
  late String fingerprint;
  late String jobId;
}

@collection
class EventRecord {
  Id id = Isar.autoIncrement;
  @Index(composite: [CompositeIndex('sequence')], unique: true)
  late String jobId;
  late int sequence;
  late String phase;
  late String code;
  String? evidenceJson;
  late DateTime at;
}

@collection
class MetadataRecord {
  Id id = 1;
  int schemaVersion = 1;
  bool profilesInitialized = false;
}
