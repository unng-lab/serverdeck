import 'package:isar_community/isar.dart';

part 'automation_records.g.dart';

// Ordinary bounded JSON rows in the single schema3 workspace. Payload validation,
// references and admission quotas belong to the shared repository.
@collection
class StoredMcpGrant {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredDelegation {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationProfile {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationRevision {
  Id id = Isar.autoIncrement;
  // Repository key profileId:revision, not body digest.
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationPlan {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationApproval {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationJob {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredDesiredState {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationReceipt {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

@collection
class StoredAutomationEvent {
  Id id = Isar.autoIncrement;
  // Repository key jobId:sequence, preserving positive int64 sequence.
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

const automationOnlySchemas = <CollectionSchema>[
  StoredMcpGrantSchema,
  StoredDelegationSchema,
  StoredAutomationProfileSchema,
  StoredAutomationRevisionSchema,
  StoredAutomationPlanSchema,
  StoredAutomationApprovalSchema,
  StoredAutomationJobSchema,
  StoredDesiredStateSchema,
  StoredAutomationReceiptSchema,
  StoredAutomationEventSchema,
];
