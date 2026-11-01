# Independent review: finite direct SSH connections

Date: 2026-11-01. Reviewer: direct_ssh_connections_review_1, fresh context, read-only.

Замечаний не найдено.

Готовность к реализации: готов — в пределах connection/session increment. Полная миграция direct SSH остаётся незавершённой.

## Scope

Seven files in `.local/direct-ssh-connections-review-scope.txt`: existing connections.dart shared lifecycle/quota integration, new direct_connections.dart finite work/context entrypoints, hosting/owner_context.dart closed command method matrix, ssh_transport.dart and direct_ssh_transport.dart dispatch proof/fence, new direct_connection_test.dart and extended direct_ssh_transport_test.dart. Exact originals for the five preexisting files are in `.local/direct-ssh-connections-before/`. Related actor/session/bootstrap/drain/metadata sources and001spec/plan/tasks/model/contract with006/021 amendments were read.

The reviewer checked FR-SSH-001/002/004/014/015 → design/contract → T404/T406/T413/T422/T424 → acceptance scenarios. No mandatory missing decision or confirmed defect was found in this scope. Actual owner/MCP contexts, attached connection identity, shared48work/4channel limits, read/apply scopes, owner method matrix, native proof after channel open, final synchronous authorization/target/continuation before stdin.add and proof before output publication were checked. Physical SSH/native ownership survives logical cancellation; failed drain prevents new admission. The new finite path does not call helper/enrollment/release.

## Actual evidence and limits

Reviewer inspected saved evidence without rerunning: `.local/direct-ssh-connections-full-r2.exit=0`, format438files/0changes, successful analyses, root86+engine670+MCP15+protocol57+Windows8=836Dart tests,16RAM bundle groups. `.local/direct-ssh-connections-links-r1.exit=0`,1581OK/0errors/2excluded. Formatter's unrelated work/isar-encryption-implementation analysis-include warnings remain noted. The full TDD red before implementation is recorded in `.local/direct-ssh-connections-red.log/.exit=1`.

RAM/native-port and byte-port tests do not establish actual native authority, real SSH, filesystem durability, systemd/APT or DB installation. The finite port is not selected consent or job authority. Actual native gate/durable writer/through-first-SSH integration and all remaining legacy facade/callers are open implementation work. T406/T413/T422/T424 and final migration compatibility are not closed by this review.
