# Задачи006 — переход на прямой SSH

**Дата**: 2026-11-01. [План](plan.md), [спецификация](spec.md),
[общие задачи001](../001-service-foundation/tasks.md).
Новые задачи не объявляют старые рецепты или реальные установки принятыми.

## Phase 1: Catalog/preflight — SSH2 / US006.1

Независимая приёмка: AC-SSH-04/06, AC-006-1A/B/C в RAM без server component.

- [ ] T001 [US1] Зафиксировать contract/recipe validation tests для обоих продуктов в `packages/serverdeck_engine/test/remote/direct_ssh_catalog_test.dart`: exact versions, signed sources, complete pins, existing paths/data, quotas, missing tools и отсутствие remote writes; FR-SSH-003/010/014. Зависит от001 typed transport.
- [ ] T002 [US1] Реализовать read-only exact catalog и descriptor capture в `packages/serverdeck_engine/lib/remote/direct_ssh_catalog.dart`; сохранить trusted APT qualification и immutable recipe digest, без executor registry/metadata refresh; FR-SSH-010, AC-SSH-04/06.
- [ ] T003 [US1] Связать каталог/preflight с `automation/compiler.dart`, `automation/plans.dart` и `remote/reads.dart`; pins/initial settings/baselines входят в direct format2 plan; FR-SSH-004/010, AC-SSH-04/06.

## Phase 2: Подтверждение/установка — SSH2 / US006.2

Независимая приёмка: AC-SSH-05/10, AC-006-2A/B/C, оба продукта и отказные cases.

- [ ] T004 [US2] Написать meaningful unit cases в `packages/serverdeck_engine/test/remote/direct_ssh_install_test.dart` для native-lock contention/подмены transaction/NetBird/SQL/settings/partial failure обеих БД; FR-SSH-005/006/010/015. Зависит отT003 и001 host reservation.
- [ ] T005 [US2] Реализовать fixed installation scripts и одноразовый native APT protocol3 gate в `packages/serverdeck_engine/lib/remote/direct_ssh_install.dart`, без установленного helper/Ansible; запрет соседних package changes, data overwrite и unverified success; FR-SSH-001/005/010.
- [ ] T006 [US2] Реализовать exact configuration/version/service/loopback/SQL/effective-settings postchecks и подключить к общему step result в `remote/direct_ssh_install.dart`, `automation/compiler.dart`; FR-SSH-009/010, AC-SSH-05.

## Phase 3: Failure/recovery и polish — SSH3 / US006.3

- [ ] T007 [US3] Связать оба install recipes с единым `automation/jobs.dart` cancel/reconcile/unknown/duplicate/authority path и unit cases; не убивать apt/dpkg, не replay при потере ответа; FR-SSH-006/007/008/009, AC-SSH-07/08/09/10.
- [ ] T008 [US3] Удалить заменённые server recipe packaging/runtime dependencies после переноса используемых проверок; обновить release notices/docs и пройти full001 checks/links/independent review; FR-SSH-013, SC-SSH-01–04. Данные серверов не удалять.

## Dependencies и implementation strategy

T001 → T002 → T003 → T004 → T005 → T006 → T007 → T008.
Основной controller/transport/host state machine001 — обязательная зависимость,
не дублирующая реализация. Независимые unit data tables обоих продуктов могут
проверяться параллельно в одном suite; одни source files меняются последовательно.
MVP — read-only каталог/blocked reasons без изменения сервера; выпуск всей
поправки требует обоих продуктов, проверки failure paths и completed review.

## UI-компоненты и приёмка (003.4)

Следующая очередь относится только к уже объявленным UI-сценариям [спецификации](spec.md) и [контракту применения](../003-design-system/contracts/feature-adoption.md). Она не открывает новые backend возможности и не стирает completed tasks. Если mapping соответствующего сценария уже выполнен, приложить его фактическое evidence вместо повторной реализации; текущий gate не расширяется.

- [ ] T022 Зафиксировать в плане mapping всех строк UI-раздела: C ID/вариант, конкретный owner/adapter, данные/события и применимые состояния/N/A. Отсутствующий вариант оформить сначала в 003. FR-UI-006-01–03 / AC-UI-006-01.
- [ ] T023 В соответствующем разрешённом UI-этапе собрать перечисленные композиции из готовых Deck/Material+BrandTheme элементов, сохранив validation, identity/readiness/revision guards и сервисные callbacks. Не переносить I/O/credentials/retry/authority в widgets. После T022; AC-UI-006-01,02.
- [ ] T024 Проверить предметные normal/failure/boundary пути и применимые UI gates 003; записать commands/scope/evidence и N/A, пройти обязательный independent review/fix loop. При unit-only gate UI/native evidence оставить явно pending до отдельной квалификации. После T023; AC-UI-006-02,03.

- [x] T025 Уточнить UI-поправку 006 по send/result proof: disconnect до возможной отправки не означает unknown, после possible send без correlated result — unknown, доказанный terminal сохраняется. Три случая закреплены в AC-UI-006-02; actual UI assertions остаются будущей T024. Исправление [review round1](../003-design-system/reviews/2026-11-01-feature-ui-adoption-round1.md), без изменения direct-SSH контракта.
