# Requirements checklist: точный перенос базового интерфейса

**Purpose**: Проверка качества требований текущей 003.4 перед Implement. `[x]`
означает одобрение текста reviewer, а не пройденный тест или приёмку приложения.
**Created**: 2026-10-28
**Feature**: [003](../spec.md)
**Owners**: автор готовит требования; независимый reviewer оценивает frozen пакет;
автор переносит только фактический результат отчёта. Implement не ставит markers.

Заполненные markers ниже сохраняют историческое одобрение прежней редакции.
После последнего прямого указания об удалении reference-инфраструктуры текст
актуализирован; новое independent review этой редакции ещё не выполнено.

## Полнота и граница

- [x] CHK001 Зафиксировано ли буквальное решение пользователя: сначала дизайн и интеграция реализованной базы, затем отдельные функционально-визуальные пакеты? [Completeness, Spec §Clarifications 2026-10-28]
- [x] CHK002 Названы ли все37 base ID и их существующие владельцы без исключения11/93 по прежнему флагу implemented? [Coverage, Spec §FR-003-LOCAL-09/10, screen-map]
- [x] CHK003 Распределены ли остальные61 ID и их функции по отдельным пакетам с обязательным дизайном, без потери любого из98? [Coverage, Spec §Scope, design-delivery]
- [x] CHK004 Отделены ли инвентаризация/поиск ПО от установки конкретных recipes, а непринятые Ubuntu Core и набор провайдеров — от обязательств текущей003? [Consistency, Spec §Clarifications 2026-10-28]

## Композиция и независимый эталон

- [x] CHK005 Определены ли для каждого base ID состав и порядок областей, поля, controls и обычный пользовательский вход? [Completeness, Spec §FR-003-BASE-01/02]
- [x] CHK006 Определены ли измеримые геометрия, отступы, шрифтовые роли, иконки, surfaces и правила source-priority при конфликте HTML/брендбука? [Clarity, Spec §FR-003-LOCAL-08, full-application]
- [x] CHK007 Зафиксированы ли independent source identity, происхождение reference PNG и запрет назначать первый Flutter capture своим эталоном? [Measurability, Spec §FR-003-BASE-03]
- [x] CHK008 Различаются ли viewport и full-page reference, предусмотрена ли проверка оставшегося scroll без масштабирования всей страницы? [Clarity, Spec §FR-003-BASE-03, full-application]
- [x] CHK009 Описана ли source-derived адаптация200% без выдуманного исходного200%PNG, browser zoom и растягивания готовых изображений? [Completeness, Spec §FR-003-BASE-03]
- [x] CHK010 Не позволяет ли критерий закрыть композицию одной палитрой, стандартными Material icons, отсутствием overflow или representative одного семейства? [Consistency, Spec §AC-003-1A, SC-003-BASE-01]

## Данные, действия и владение

- [x] CHK011 Имеют ли все существующие показанные действия concrete callback, контекст цели и проверяемый результат вместо demo уведомления? [Traceability, Spec §AC-003-1B, screen-map]
- [x] CHK012 Определено ли владение server/automation lifecycle при переходах между5разделами, сохранении контекста, закрытии и смене private epoch? [Completeness, Spec §FR-003-LOCAL-04/14, plan]
- [x] CHK013 Сохранены ли existing contracts, authority, revisions, consent, pending/unknown и запрет нового SSH/store/автоматического эффекта? [Consistency, Spec §FR-003-LOCAL-06/07/14]
- [x] CHK014 Описаны ли locale search/filter/tab/summaries по реально доступным профилям/наблюдениям без притворного connected/health статуса? [Clarity, Spec §Scope, FR-003-LOCAL-13]
- [x] CHK015 Различаются ли реальная пустота, отсутствие замера, отказ, stale, dropped, incomplete и unknown; определены ли source/time и gaps? [Coverage, Spec §FR-003-LOCAL-07/12/13]
- [x] CHK016 Требуются ли production-компоненты и ordinary installed routes; исключены ли отдельная gallery, ModelClient/test fixtures и HTML-просмотрщик в обычном runtime? [Consistency, Spec §FR-003-BASE-02]

## Адаптация, защита и состояния

- [x] CHK017 Определены ли все592 сочетания37×4frames×2themes×100/200%, границы перестройки, keyboard inset и достаточно длинные/Unicode данные? [Coverage, Spec §SC-003-BASE-01, FR-003-LOCAL-05/11]
- [x] CHK018 Описаны ли44px targets, keyboard traversal, focus visibility, semantics, reduced motion и текстовые значения графиков? [Completeness, Spec §FR-003-LOCAL-02/05/11/12]
- [x] CHK019 Сохраняют ли error/empty/loading/denied/unsupported варианты композицию соответствующего базового экрана без объявления отсутствующего будущего сервиса работающим? [Consistency, Spec §AC-003-1B/3A]
- [x] CHK020 Сохраняются ли host-key change, protected effect, unknown job и storage protection как разные причины с допустимым следующим шагом? [Coverage, Spec §FR-003-LOCAL-07, screen-map11/93]
- [x] CHK021 Определено ли скрытие приватной цели, модальных экранов, секретного ввода и поздних ответов при retirement без удаления данных? [Coverage, Spec §AC-003-3B, FR-003-LOCAL-14]

## Проверки, история и установленный результат

- [x] CHK022 Ограничены ли локальные и CI проверки static/unit/widget; отделены ли compile/package/install/show от невыполненных native/integration workloads? [Consistency, Spec §Clarifications 2026-10-28, Constitution VII]
- [x] CHK023 Связана ли каждая новая обязанность цепочкой requirement→decision→contract→task→проверяемый критерий без TBD для текущей реализации? [Traceability, Spec §FR-003-LOCAL-10, tasks]
- [x] CHK024 Сохранены ли completed task lines/markers и failed/skipped scopes; отменённые пользователем infrastructure ID явно отмечены CANCELLED, а новая приёмка отделена от старых заявлений? [Consistency, Spec §Status, Constitution VI/VII]
- [x] CHK025 Определены ли independent code/spec/visual review, freeze входов, fix-loop и условия повторных проверок? [Completeness, Spec §SC-003-LOCAL-04, AGENTS]
- [x] CHK026 Включает ли завершение новую фактическую установленную сборку с версией/source identity, сохранностью данных, shortcut и обычным UI показом? [Acceptance, Spec §FR-003-BASE-04, SC-003-BASE-02]
- [x] CHK027 Запрещено ли переносить приёмку003 на61будущий экран или объявлять unit pass платформенной/целопродуктовой квалификацией? [Consistency, Spec §SC-003-LOCAL-01, FR-003-BASE-04]
- [x] CHK028 Определены ли текущий статус каждой проверки и остаток работы, чтобы цель не закрывалась по одним markers либо макетам? [Acceptance, Spec §SC-003-BASE-01/02, evidence/handoff]

## Notes

Первоначальное состояние было28/28 unchecked; последующее одобрение относится к прежней редакции, а не к текущим изменениям. Этот checklist оценивает требования и не содержит результатов тестов.
