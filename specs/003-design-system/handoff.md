# Локальная передача дизайна ServerDeck

Актуально на 26 октября 2026 года. Обновлён существующий пакет 003. Реализация этапов 003.1–003.3 принята в согласованных границах UI: [независимое ревью кода](reviews/2026-10-26-code-0033-03.md) и [визуальное ревью](reviews/2026-10-26-visual-0033-08.md) завершены без замечаний. [Содержательное ревью итоговых документов](reviews/2026-10-26-docs-003-final-01.md) T043 завершено без замечаний; первоначальные 102 задачи закрыты; последующий recording audit и read-only Converge завершены, результат зафиксирован в чате. При подготовке source-preview дополнительно закрыты локальные implementation-задачи T103–T107; теперь107 уникальных задач. Внешний post-commit CI остаётся обязательным до merge и source publication. История задач, обнаруженных ошибок и исправлений сохранена в [tasks](tasks.md) и [evidence](evidence.md).

## Что передаётся

- [Автономный атлас 98 экранов](../../docs/design/ServerDeck-design.html), работающий локально без Figma и сети. [Реестр](../../docs/design/screens.json) сохраняет 98 ID и 33 источника. Основа — [брендбук 1.1](../../docs/brandbook/README.md) и [точные токены](../../docs/brandbook/tokens/serverdeck.tokens.json); шрифты, логотипы и лицензии сохранены.
- 35 существующих UI-сценариев связаны с production-компонентами и фактическими результатами в [карте экранов](screen-map.md). Остальные 63 экрана — концепты профильных пакетов. Новые серверные функции ради этих макетов не реализовывались.
- Светлая и тёмная темы; логические размеры 1100×760, 800×600, 390×800 и 360×800; текст 100% и 200%. Узкие размеры проверяют адаптивный Windows-клиент, а не новую мобильную платформу.
- Контекст, клавиатура, фокус, доступные имена, области нажатия, графики, ошибки, неизвестный исход и удаление приватных данных проверены в оговорённых границах.

Последнее исправление T102 защищает подпись полной записи журнала. Имя и адрес показываются только при совпадении ID и ревизий соединения, credentials и доверия. Старая запись не получает новый адрес; при несовпадении видны причина и следующий шаг. Источник, время записи и время наблюдения сохраняются. Новых запросов, cache или владельцев состояния это не добавляет.

## Фактическая проверка

F16 — четыре размера × две темы × два масштаба текста. P4 — desktop 1100×760 в двух темах при 100% и phone 360×800 в двух темах при 200%.

| Проверка | Результат | Граница |
| --- | --- | --- |
| Root Dart format | 657 файлов, 0 изменений, exit0 | Сохранены warnings lint resolution в ignored work |
| Flutter analyze | 0 issues, exit0 | Flutter 3.47.7 / Dart 3.13.5 |
| Flutter test | 7448 passed + 1 ожидаемый opt-in skip, exit0 | Весь текущий root suite; F16 nonprivacy и P4 private transitions |
| Default Windows build + smoke | Новая сборка; 2 passed, 19 секунд, 12 PROVED markers, exit0 | Без SkipBuild; synthetic startup/profile/settings/reopen; без SSH/install/executor effects |
| Baseline05 | 560 тестов, 744 PNG, 35 origins × F16 | Все 744 изображения совпали с baseline04; прежняя визуальная приёмка переносится только по identity и scope |
| State05 | 2573 теста, 4580 PNG, 253 ID, 35 origins, P4, exit0 | 253 applicable cases и 167 source-backed N/A; 16 новых checkpoints T102; missing/unexpected — 0 |
| Bounded scroll | 48 тестов, 64 PNG, exit0 | Старая схема 003.2/T087: два component cases; дополнительные unresolved F16 tests выполняют все assertions, пропуская только writer |
| Strict links этапа T102 | 1435 total / 1434 OK / 0 errors / 0 timeouts, exit0 | Полный glob specs; network scheduling options записаны в evidence |
| Reference validator / diff check | 0 ошибок, exits0 | Статические ссылки/эталоны и whitespace, не runtime acceptance |
| Независимые code / visual reviews | Оба завершены, 0 замечаний | 94 source + 59 package + 8 owners frozen; 10760 PNG hashes/mappings и 28 просмотренных visual inputs |

Current F16 подтверждены compiled registration и полным root pass. Отдельный завершённый 4272-test run или current F16 per-ID JSON не заявляется; exact current capture join имеет P4. Прерванный combined6491 не считается успешным. Static Dart descriptors остаются planned/notRun, фактическое evidence хранится отдельно. Сохранены native integration_test diagnostic и CRLF advisories.

[Финальная сверка целостности](reviews/2026-10-26-boundary-003-final.md) завершена без замечаний. Исходный reference export содержит 784 PNG, 17 contact sheets и ZIP из 832 файлов; все изображения заново декодированы, каждый ZIP member перечитан и побайтово сопоставлен с original export. Его integrity отделена от Flutter captures и визуальной приёмки. Desktop/compact reference PNG могут иметь full-page высоту. Канонический DESIGN.md — исправленная revision; исходный ZIP не объявляется её обновлённой копией.

## Spec Kit

| Этап | Запись |
| --- | --- |
| Constitution | Существующая 3.0.1 проверена; пересоздание принципов не требовалось |
| Specify / Clarify | [Спецификация](spec.md), прежние ID сохранены; обязательных вопросов по доступным источникам не осталось |
| Plan | [План](plan.md), [research](research.md), [модель](data-model.md), [P01–P12](contracts/presentation.md) |
| Checklist / Tasks / Analyze | Requirements 16/16; 102 стабильных task ID; цепочка 16 FR / 4 SC / 9 AC / P01–P12 / A01–A12 проверена независимо |
| Implement / Review | 003.1–003.3 и corrective T100/T102 завершены; clean code03/visual08; T042 сверён; T043 завершён clean docreview01; 102/102 задачи закрыты |
| Converge | Финальная read-only проверка spec/plan/tasks и кода выполняется после документального gate; фактический итог сообщается в чате. При отсутствии gaps tasks остаётся byte-identical |
| Taskstoissues | Не применяется к этой локальной передаче: GitHub issues, PR, merge и публикация не поручены |

## Воспроизведение

[Quickstart](quickstart.md) содержит prerequisites и команды root format/analyze/test, links/validator/default Windows и opt-in captures в свежие sibling directories. Fixture data синтетические. Каталог `.local` содержит локальную диагностику, не обязательные runtime/release assets или portable CI inputs.

В текущем workspace доступны `.local/design-003/003.3/baseline-final-05/gallery.html`, `.local/design-003/003.3/state-final-05/server/gallery.html`, raw logs, actual exit sidecars и inventories. Эти helpers не подключаются к инфраструктуре и не заменяют приложение. На другом checkout captures создаются заново по quickstart. Полные результаты, SHA и границы проверок — в [evidence](evidence.md).

Полная приёмка 001/021, genuine remote Panel RPC/SSH authority, backend durability и runtime 63 concepts находятся вне design scope. Production API/storage/controllers/dependencies не заменялись ради макетов; посторонние executor/CI/native/021 изменения сохранены. Коммитов, PR, merge и публикации в этой передаче не выполнялось.

## Source-preview follow-up — 2026-10-26

По отдельному поручению владельца подготовлена версия0.2.0-preview.1+2 и выбрана MIT для исходного кода; third-party licenses сохранены. T103 исправляет переносимость canonical snapshots и metadata references; T104 добавляет readable target в оба revoke-dialog; T105 сохраняет полное painted JSON-error. T106 исправляет только старые native fixture expectations/order, T107 отделяет ручной full-product marker от неизменённого автоматического MCP CI без удаления исполнимых тестов.

Актуальные локальные результаты: full root format625/0changes, analyze0issues, Flutter7505passed/1opt-in-skip; default fresh Windows bootstrap2passed/12markers/exit0. Full locald analyze0, serial native suite930passed/1skip/exit0 с private cached provider; skip — Linux SSH container, запускаемый отдельным Linux CI job. Canonical validator98/35/63/33, Python12, strict fullglob links и diffcheck успешны. T10441focused/105related/108privacy,32captures/visualQA0; T10516F16/89related/467flows,16captures/visualQA0. Fresh independent UI/source review и native/CI review завершены без замечаний.

Локальные implementation-задачи T001–T107 завершены; это не утверждение успешного GitHub CI. Следующий внешний gate — MCP automatic checks на точной commit revision, terminal success обязателен до merge/source release. Его commit/run/conclusion фиксируются отдельно после выполнения. Подготовка/commit/PR не равны публикации; до фактического результата CI merge/source release запрещены.

Публичная поставка этого preview содержит только source ZIP и SHA-256. Полный Windows bundle предназначен для отдельно проверяемой локальной review-установки с сохранением format3workspace; сертификат издателя/native distribution и full001/021/005 не квалифицированы. Source-preview, локальная установка и production readiness не смешиваются. Старые source/captures/failed checks/reviews сохранены; raw follow-up diagnostics находятся в локальном `.local/release/`, не являются runtime/release assets.
## T108 follow-up после CI

T001–T107 остаются завершённой локальной историей. Обе попытки PR40372935619 на A933 failed на разных Windows harness cases; merge/source publication не выполнялись. T108 добавлен для отделения cold compilation от прежнего behavioral watchdog, bounded owned fixture cleanup и safe phase/numeric diagnostics, с новыми обязательными проверками и fresh independent review. Следующая сборка0.2.0-preview.1+3 подготовит новые commit/source/artifacts и локальную установку с сохранением уже установленной+2. До нового успешного terminal MCP CI на точной revision внешний gate остаётся незакрытым; public binary/full001/021/005 acceptance не заявляются.

T108 локальные проверки завершены: root627/0format, analyze0,7505passed/1skip; Windows analyze0 и134nativepassed; diagnostics10PASS с25cleanup/21pipeвариантами. Fresh independent review кода/пакета и последующая запись его результата ещё обязательны до commit; новый external CI, сборка/установка+3 и source publication не выполнены.

Локальная реализацияT108 прошла fresh independent code/spec review:0findings и0PowerShell subaudit; задачиT001–T108 закрыты в локальном implementation scope. Checkbox прямо исключает ещё не выполненные post-commit build/install/tag/CI/publication. Следующий непосредственный шаг — проверка ссылок и fresh recording review трёх изменённых документов; до его чистого результата commit не выполняется. После commit обязательны новый exact-revision successful MCP CI, проверенный+3Release bundle, новая локальная установка и source-only публикация.

## T109: CI scheduling follow-up

После завершённой локальной T108/+3 установки подтверждён outer timeout старого A933push40372896426. Общий SID mutex уже защищён последовательным режимом tracked dart_test.yaml; предположение о фактическом параллельном CI было исправлено до commit. T109 задаёт serial locald, fail-fast при уже возникшей ошибке и240min outer CI budget без изменения individual/runtime bounds или набора успешных checks. T001–T108 не переоткрываются; T109 implementation/checks/review ещё выполняются. Следующий metadata build+4 потребует собственного commit/build/install/source/tag и terminal exact-revision CI; +3 и workspace сохраняются. Ни one cancelled run, ни отсутствие failure projection не объявляются успешной приёмкой.

T109 локальные проверки конфигурации и metadata+4 завершены: actual PS argument-block mock/parse/workflow diff, pinned CLI flags, root627/0/analyze0/7505passed1skip. Package YAML прежде уже сериализовал locald; CLI1 закрепляет это явно. Новый240min budget и fail-fast не утверждают отсутствие других ошибок или завершённость CI. Fresh code/spec review и recording audit ещё обязательны до commit; новая+4поставка пока не выполнена.

Fresh t109_independent_review и installer narrow subaudit завершились0findings. Локальные задачиT001–T109 закрыты; это не successful CI или выпуск+4. Перед commit остаётся recording audit трёх документов после link check; затем обязательны новый точный commit/terminalCI/проверенные+4build-install-source/tag/publication receipts. Ни общий240min ceiling, ни явныйCLI1 не превращают прежнюю отмену/unknown errors в успешную qualification.

## T110 follow-up

Новый2af push CI остановлен fail-fast на bootstrap aggregate4min timeout без фазы; T110 разделяет bounded fixture preparation и прежнее4min behavior, добавляя fixed print phase projection. Все runtime assertions/deadlines/authority остаются; это не установленная production причина и не успешная cold qualification. Локальные T001–T109 сохраняются, T110 ещё выполняется. Следующий metadata+5 потребует своих actual checks/reviews/commit/build/install/source/tag и успешного exact-revision CI; private+4 и данные сохраняются, source publication/merge не выполнены.

T111 диагностический follow-up учитывает второй CI4PR failure: trust-probe child55s timeout с неизвестным mode. Добавляется fixed36-case projection, без изменения actor/runtime/55s/80s и без объявления реальной причины устранённой. T110/T111 metadata+5 ещё локально проверяются; новый actual successful exact-revision CI обязателен, current installed+4/data сохраняются.

T110/T111 локальные проверки завершены: root628/0/analyze0/7505pass1skip, modifiedbootstrap preparation12.6s+behavior198.3s/17phases, fullseriallocald930pass1skip54m30exit0, controlleddiagnostics12PASS/exit0. Это cached native scope, не cold qualification и не доказанная причина старого probe timeout. Следующий gate — fresh independent code/spec/helper+5 review и отдельный recording audit до нового commit.


### T110/T111: fresh independent review завершён

t110_t111_independent_review завершён без замечаний; отдельный read-only diagnostics subaudit также0. Все9size/SHA review-T110-T111.json совпали в начале и конце, HEAD2af сохранён. Проверены bootstrap preparation/ownership/cleanup, сохранность прежних behavior/oracles/deadlines, fixed17phase/36case projection и installer+5 literal guard; cached local evidence не расширено до coldCI. T110/T111 закрыты только в локальном implementation/checks/review scope, T001–T109 и все RED сохранены. После этой записи обязательны fresh links и отдельный recording audit до commit. Новый exact commit, terminal successful CI, build/install/source/tag/merge/publication ещё не выполнены для+5.
