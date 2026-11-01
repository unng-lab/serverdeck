import 'package:isar_community/isar.dart';

import 'package:serverdeck_engine/storage/automation_records.dart';
import 'package:serverdeck_engine/storage/records.dart';

part 'host_trust_records.g.dart';

// Target schema3 metadata only; declarations never open a database.
@collection
class StoredHostTrust {
  Id id = Isar.autoIncrement;
  @Index(unique: true, caseSensitive: true, replace: false)
  String entityId = '';
  String payload = '';
}

const workspaceSchemas = <CollectionSchema>[
  ...foundationSchemas,
  ...automationOnlySchemas,
  StoredHostTrustSchema,
];
