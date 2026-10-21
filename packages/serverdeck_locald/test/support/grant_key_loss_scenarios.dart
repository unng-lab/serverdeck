import 'package:isar_community/isar.dart';
import 'package:serverdeck_locald/mcp/grants.dart';
import 'package:serverdeck_locald/storage/automation_records.dart';
import 'package:serverdeck_locald/storage/key_custody.dart';
import 'package:serverdeck_locald/storage/state_store.dart';
import 'package:serverdeck_windows/mcp_credential_files.dart';
import 'package:serverdeck_windows/mutex.dart';

import 'grant_transaction_scenarios.dart';
import 'operational_open_scenarios.dart' show refusal;
import 'operational_snapshot_child.dart' show check;

const grantKeyLossModes = {
  'grant-key-closed-admission',
  'grant-key-closed-queued',
};

Future<void> verifyNativeGrantKeyLoss({
  required StateStore store,
  required String mode,
  required String root,
  required String bundle,
  required ReceiptKeyMaterial key,
  required KeyCustody custody,
  required MutexLease lease,
  required McpCredentialFiles files,
}) async {
  final before = store.operational;
  final count = credentialFiles(files);
  final service = OwnerGrantService(store);
  final request = grantCreate(700, 701);
  if (mode == 'grant-key-closed-admission') key.close();
  final result = service.submitOwner('grant.create', request);
  if (mode == 'grant-key-closed-queued') key.close();
  await refusal(() => result);
  check(!store.isAutomationReady);
  await refusal(() async => store.operational);
  await refusal(() => service.submitOwner('grant.create', request));
  check(credentialFiles(files) == count);
  final native = Isar.getInstance('workspace')!;
  check(await native.storedMcpGrants.count() == 0);
  check(await native.storedAutomationReceipts.count() == 0);
  await store.close();

  // Reusing the disposed key is forbidden. Recovery opens the actual protected
  // wrapper again and validates the complete native workspace under the lease.
  final recoveredKey = await custody.openReceiptKey(
    key.wrapper,
    key.workspaceId,
    key.receiptKeyId,
  );
  StateStore? recovered;
  try {
    recovered = await StateStore.openOperational(
      localAppData: root,
      appRoot: bundle,
      lease: lease,
      custody: custody,
      receiptKey: recoveredKey,
    );
    check(recovered.isAutomationReady);
    baselineRetained(before, recovered.operational);
    await OwnerGrantService(recovered).submitOwner('grant.create', request);
    check(recovered.operational.automation.grants.length == 1);
    check(recovered.operational.automation.receipts.length == 1);
  } finally {
    if (recovered != null) await recovered.close();
    recoveredKey.close();
  }
}
