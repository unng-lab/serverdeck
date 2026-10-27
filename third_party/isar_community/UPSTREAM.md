# Isar Community Dart runtime source

Upstream: isar_community 3.3.2, Apache-2.0; LICENSE is retained verbatim.

Source archive: https://pub.dev/api/archives/isar_community-3.3.2.tar.gz

Archive SHA256: `683fd093956eac3a660776afb70d65d50a3391b3587b40b89e3d12586b8cc47f`.
The archive digest was verified before copying its complete lib/ runtime tree.
Upstream tests/tools/examples are not included in this runtime-source package.

Local package identity: 3.3.2+serverdeck.1, publish_to none. Native ABI and
Isar.version remain 3.3.2; the separately qualified native artifact is unchanged.
Locald and the root Flutter package explicitly select this directory in their
pubspec overrides and checked lockfiles. The generator's hosted runtime
constraint is resolved to this same selected local runtime.
The generator remains upstream 3.3.2.

Runtime changes relative to the archive:

- `lib/src/common/isar_common.dart`: async/sync wrappers abort failed callbacks
  only if the transaction is still active. A failed native commit consumes the
  transaction and must not be finished a second time.
- `lib/src/native/txn.dart`: async commit/abort always await reply-subscription
  cancellation in finally after native finish/reply, including reported errors.
- Runtime source may be formatted by the pinned project Dart SDK. No native
  declarations, schemas, web implementation or other runtime behavior is changed.

Metadata changes: local version/publish prohibition above; the local analyzer
configuration retains upstream's generated native-bindings exclusion without
requiring its external development lint configuration. It also excludes the
unchanged, unused legacy web backend, which imports dart:indexed_db removed
from the pinned SDK; ServerDeck qualifies its native Windows runtime. Other pubspec contents
are retained. Root required formatting, analysis, real native transaction tests
and independent review apply to these changes.

Acceptance and scope: [native transaction contract](../../specs/021-mcp-control/contracts/native-transactions.md).
This source copy does not qualify or enable a native DLL, installed bundle,
operational startup or any remote executor.
