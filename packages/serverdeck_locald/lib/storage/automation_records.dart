import 'package:isar_community/isar.dart';

import 'records.dart';

part 'automation_records.g.dart';

// Same ordinary bounded JSON-row representation as schema1. Payload validation,
// workspace references and admission quotas belong to the shared repository.
// Declaring these schemas alone must never migrate/open the active schema1 DB.
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
const automationWorkspaceSchemas = <CollectionSchema>[
  ...workspaceSchemas,
  ...automationOnlySchemas,
];
