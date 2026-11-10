# Implementation Plan: Журналы сервера

**Date**: 2026-11-04 | **Spec**: [spec.md](spec.md) | Ветка: текущая рабочая.

## Summary

Вкладка журналов выбранного сервера, loaded systemd services и вручную заданные файлы. Один JournalsOwner, закрытая typed SSH capability, bounded exec, тот же Isar/store. История и checkpoint атомарны, окно получения60мин плюс хвост200/источник независимо от возраста (caps приоритетны), ограниченные storage/reads и явная неполнота.

## Technical Context

- Dart>=3.13.5, Flutter, vendored dartssh2, isar_community3.4.1. Новых зависимостей нет.
- Windows desktop; remote POSIX shell, GNU stat/dd и procfs для файлов, systemctl/journalctl>=236 для journal. Не устанавливать prerequisites автоматически.
- Storage: новая JournalSource коллекция в WorkspaceStore, config+checkpoint+entries JSON на источник. Тот же DomainRepository и единая транзакция с pruning. Current-only schema, без миграций/совместимости/очистки несвязанных данных.
- Unit/functional widget fakes и synthetic channels; никакого реального Isar, integration/e2e/VM/design acceptance.
- Poll5s, deadline≤5s, максимум4 jobs005 глобально и1/profile. Общая bounded FIFO admission очередь004/005 перед shared exec slot, deadline включает очередь; отменённый waiter не dispatch. Protocol tombstone busy означает waiting и следующий tick, без отмены здорового monitoring. Fair round robin по16 источникам; SC-502 при свободном slot для одного готового источника; due очередь явно показывается независимо от старого partial/ready.
- Remote stdout+stderr64KiB, journal page200, file chunk16KiB, pending fragment16KiB. Discovery500, settings16/profile; storage limits FR-510.

## Constitution Check

До research и после design: I — готовые C02/C03/C04/C06/C07/C08/C10/C11/C12/C13/C14/C20/C28; II — без дизайна feature screens; III — unit/fake only; IV — тот же Flutter/Isar/EXE; V — runtime живёт в трее, shutdown drain; VI — current-only, без migration/backfill. Исключений нет.

## Project Structure

```text
lib/journals/journal_models.dart   # config/events/checkpoint/validation
lib/journals/journal_protocol.dart # closed requests, safe scripts, parsers
lib/journals/journal_port.dart     # private typed capability/job
lib/journals/journal_owner.dart    # storage, scheduler, TTL/caps/fences
lib/journals/journal_view.dart     #001 composition, functional actions
lib/journals/delete_source_dialog.dart #001 confirmation, local error/draft state
lib/connections/connection_owner.dart # gate admission and result fences
lib/connections/ssh_transport.dart # JournalSshConnection implementation
third_party/dartssh2/lib/src/ssh_client.dart # bounded stderr/nonzero opt-in
lib/storage/records.dart + records.g.dart # JournalSource
lib/storage/domain_repository.dart # CRUD and atomic profile cleanup
lib/runtime/feature_runtime.dart # composition and lifecycle
lib/runtime/runtime_view.dart # owner injection
lib/profiles/profile_view.dart # replace Journals placeholder
test/journals/ # unit/fake functionality
test/connections/ # synthetic protocol/owner tests
test/fixtures/domain_repository.dart # detached in-memory sources
```

## Phases

0. [Research](research.md): reuse bounded exec cancellation, no unbounded SFTP. Fixed scripts and safely quoted validated data only. Preserve monitoring default semantics, opt-in stderr/nonzero result for005.
1. [Data model](data-model.md), [contract](contracts/journals.md), [validation guide](quickstart.md): atomic batch/checkpoint and invalidation, no raw commands/payload in MCP/diagnostics.
2. [Tasks](tasks.md): foundation, US1, US2, US3, tests/checks/review; each story isolated with fakes.
3. Implement→converge; append new work without erasing completed tasks.

## Complexity Tracking

Search refinement FR-515 (user correction) reuses C05 in lib/journals/journal_view.dart and test/journals/journal_search_test.dart: filter discovered unit names and configured source name/target before their lists, independent of current selected source and record pagination. Source selection/discovery retain query; server/revision/owner reset it. No owner/storage/transport/schema changes or message filtering.

Нет исключений. Per-source JSON — bounded transaction unit; глобальная очистка в каждой записи. UI не владеет SSH/Isar.

Уточнение 2026-11-10: FR-506/507 реализуются общим retainedJournalEntries для projection/prune; expiry timer учитывает только записи вне хвоста200 и файловый prefix. Новый сеанс заново читает journal tail200 без --since, затем cursor200. Wire/schema v1 и prerequisites не меняются.
