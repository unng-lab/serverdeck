import 'package:isar_community/isar.dart';

import 'automation_records.dart';

part 'host_trust_records.g.dart';

// Declaration only. Active format2 loaders must continue to refuse schema3.
@collection
class StoredHostTrust {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

const trustedWorkspaceSchemas = <CollectionSchema>[
  ...automationWorkspaceSchemas,
  StoredHostTrustSchema,
];
