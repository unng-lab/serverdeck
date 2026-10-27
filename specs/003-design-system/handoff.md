# Локальная передача дизайна ServerDeck

Актуально на 27 октября 2026 года. Обновлён существующий пакет 003. Реализация этапов 003.1–003.3 принята в согласованных границах UI: [независимое ревью кода](reviews/2026-10-26-code-0033-03.md) и [визуальное ревью](reviews/2026-10-26-visual-0033-08.md) завершены без замечаний. [Содержательное ревью итоговых документов](reviews/2026-10-26-docs-003-final-01.md) T043 завершено без замечаний; первоначальные102 задачи закрыты, последующие T103–T113 завершены в своих локальных scopes. Теперь115 уникальных задач; T114/T115 завершены только в local implementation/checks/review scope: readiness и fresh Dart/PS implementation reviews дали0 findings, фактические local checks выполнены. Отдельный final recording review ещё обязателен до commit. Фактически установлена private+6 из29c0521; общая metadata+7 подготовлена для T114/T115. Внешний post-commit successful fullCI остаётся обязательным до merge/tag/source publication. История задач, обнаруженных ошибок и исправлений сохранена в [tasks](tasks.md) и [evidence](evidence.md).

## Что передаётся

- [Автономный атлас 98 экранов](../../docs/design/ServerDeck-design.html), работающий локально без Figma и сети. [Реестр](../../docs/design/screens.json) сохраняет 98 ID и 33 источника. Основа — [брендбук 1.1](../../docs/brandbook/README.md) и [точные токены](../../docs/brandbook/tokens/serverdeck.tokens.json); шрифты, логотипы и лицензии сохранены.
- 35 существующих UI-сценариев связаны с production-компонентами и фактическими результатами в [карте экранов](screen-map.md). Остальные 63 экрана — концепты профильных пакетов. Новые серверные функции ради этих макетов не реализовывались.
- Светлая и тёмная темы; логические размеры 1100×760, 800×600, 390×800 и 360×800; текст 100% и 200%. Узкие размеры проверяют адаптивный Windows-клиент, а не новую мобильную платформу.
- Контекст, клавиатура, фокус, доступные имена, области нажатия, графики, ошибки, неизвестный исход и удаление приватных данных проверены в оговорённых границах.

Последнее исправление T102 защищает подпись полной записи журнала. Имя и адрес показываются только при совпадении ID и ревизий соединения, credentials и доверия. Старая запись не получает новый адрес; при несовпадении видны причина и следующий шаг. Источник, время записи и время наблюдения сохраняются. Новых запросов, cache или владельцев состояния это не добавляет.

## Фактическая проверка исходной UI-передачи 003.1–003.3

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


## T112: release gate остаётся открытым

CI5push40413693379 failed gateway-quota на stderr assertion при close119, до owned delete121; первичная причина могла быть замещена finally. PRCI5 пока выполняется, merge/tag/source release не выполнены. Установленная private+5/source ZIP5 подтверждены независимым artifact audit, но не подменяют exact successful CI. T112 сохраняет primary+secondary private error/stack в прежнем body-owned cleanup lifetime и добавляет строго проверенный bounded gateway exit projection; runtime/oracles/deadlines/actor/provider не меняет по гипотезам. T001–T111 сохранены. Следующий metadata+6 требует своих checks/reviews/commit/terminalCI/build/install/source/tag/publication; workspace и старые установки сохраняются. Spec readiness review выполняется после links до implementation.


## T113: sourcebuilt capacity reproduction и bounded sync fixture

Оба Windows CI5 failed: push gateway-quota masking и PR trust-probe-success-write-capacity55s. T112 сохраняет обе gateway ошибки; T113 сохраняет все capacity oracles/commits/map/timeouts и заменяет лишь async maintenance на отдельные sync transactions с yield16, добавляя fixed safe stages/buckets. Actual CI phase/cause не доказана. Новый sourcebuilt artifact и unchanged private baseline сначала выполняются после полного cachedT112; не активировать candidate и не менять обычные bundles/provider. Затем нужны same-artifact after-run, cached36 и все указанные local checks/reviews. Полный T112cached run не выдаётся за T113/coldCI. Metadata+6 остаётся общей будущей revision двух задач; installed+5/data/история сохраняются, full exact new CI/merge/tag/source publication ещё обязательны. Новая T113 проходит strict links/readiness review до implementation.


## T112/T113: локальные проверки закончены, review pending

T112 полный cached serialnative936passed/1skip54m26exit0 предшествовал T113Dart edits. T113 root632/0/analyze0/7505pass1skip4m40, localdanalyze0/cached36pass1m51, helper10GREEN и meaningfulRED, fullcontrolled14successful groups/exit0. Sourcebuilt197-file unqualified artifact c45bf.../fe475... использован для oldasync baseline4502ms и newcase4043ms с16raw/ID rollback+recovery/replay/revoke oracles; source/provider/bundle preservation подтверждены. Одна пара не устанавливает CI55s cause. Operational formatter longpaths/import-boundary capsule RED исправлены только переносом privateinputs вне source tree, без ослабления guard/receipts; mapping/oldRED retained. Root appsources/protocols/provideractivation не менялись.

Следующий gate — fresh independent code/spec/helper+6 review, затем recording audit перед commit. T112/T113 остаютсяunchecked; metadata+6 не собран/не установлен/не опубликован, actualprivate+5/data сохраняются. Новый exact successful full CI, commit/build/install/source/tag/merge/publication имеют отдельные receipts. Source-only/unsigned-private/signing/native-distribution/full001/021/005 boundaries прежние.


### T112/T113: fresh independent implementation review завершён

t112_t113_independent_review завершён0findings; отдельный completed PowerShell/helper+6 subaudit также0. На завершение01:32:21Z все14bytes/SHA review-T112-T113.json совпали, HEAD5461dad сохранён. Подтверждены scoped requirements/implementation/oracles, meaningfulRED/GREEN, actual checks и отдельность historicalfullT112/cached36/sameartifactpair/fullcoldCI. T112/T113 закрыты только в local implementation/checks/review scope; все113unique tasks и прежние RED/history сохранены. Причины двух CI5failures не объявлены доказанными/устранёнными. После этой записи выполняются fresh links и отдельный recording audit3docs до commit. Metadata+6 ещё не имеет новых commit/CI/build/install/source/tag/merge/publication receipts; installedprivate+5/workspace сохраняются. Exact terminal successful full CI остаётся обязательным перед merge/tag/source release, binary/signing/native distribution/full001/021/005 boundaries прежние.

## T114: existing package перед readiness review

После предыдущей записи+6 из29c05212b462b3af33c284a19c7995d4652f2500 фактически собран/установлен; artifact/source reviews завершены0findings,29bundle files/четыре workspace files/пять старых установок и1247source Git blobs проверены. Это private unsigned cached-f1 review install. Sourcebuilt c45 candidate не активирован/не квалифицирован. PR CI6 40433707316 Windows121957250368 затем failed trusted-client-oversize exit1; safe reporterComplete=true, declaration65/frame90, nativeErrors=[], phase/code null. Push40433701962 ещё выполнялся на момент начала T114, четыре Linux/executor jobs successful. Ни current fullCI success, ни merge/tag/source publication не заявлены; actual cause unknown.

Десять unchanged local oversize probes прошли; установленная source-level process-lifetime race не выдана за actual CI reproduction. [План T114](plan.md#t114--завершение-trusted-client-fixture-и-сохранение-первого-отказа) закрепляет bounded test-only completion после client finally: READY exact `TRUSTED_CLIENT_READY_TO_EXIT\n`, ACK exact `TRUSTED_CLIENT_EXIT_ACK\n`+EOF,64byte/12s client bound, streaming16KiB и один cached server Future/absolute9или12s budget. Все37 modes используют barrier: cleanup2/cleanup3 также удерживают client после actual worker.close, сохраняют server10s/cleanup5s и все close-failure assertions; phase/code для них null. Прежние outer35s/test50s bounds не меняются. Physical api.close, terminal/pending/write/identity oracles сохраняются.

Два новых Windows support helpers и два pure unit tests определены вместе с actor/parent adapters; generic runOwnedFixtureLifecycle сохраняет primary+secondary private errors через await cleanup и пригоден для других test fixtures, server пишет только first whitelisted phase/code в owned128ASCII record. Parent после actual exit до Fixture.close добавляет exact sole-first reason marker; schema1 использует только existing fixturePhase/safeCode при проверенных current hashes/35cases/producer/declaration/URL/name. Missing/corrupt/unreadable/foreign/spoof record не даёт новых полей. Запланированы meaningful unit RED/GREEN, native real stdin/earlyexit/liveness, all37cases/10oversize/fullserialWindows, root mandatory/Windows analyze/fullcontrolledPS/links/diff и fresh implementation/recording reviews.

Сейчас изменены только четыре документа003 и pubspec metadata+7. T114 unchecked; ближайший gate — strict full-spec links/diff, frozen five-file manifest и отдельный completed independent readiness review. До него implementation не передаётся. После реализации+7 отдельно нужны фактические exact commit/terminal successful fullCI/build/install/source ZIP/SHA/tag/merge/publication; local checks/review не заменяют ни один из них. Actual+6/workspace/пять старых versions, все completedT001–T113 и старые/обаCI6 run records сохраняются. Public assets остаются source ZIP/SHA only; signing/native distribution/full001/021/005 остаются открытыми.

Последующее состояние CI6: push40433701962 также failed, locald phase/trusted_auth_native_test.dart declaration127/frame155 finally/shared close119 stderr-empty, reporterComplete=true; case и primary cause ещё неизвестны. Safe proof сохранён отдельно, это новый masking follow-up вне T114 implementation. Его future task/решения требуют отдельной записи/review и не считаются закрытыми completion barrier. Общая будущая metadata+7 пока не имеет release receipts.

## T115: trusted-auth перед отдельным readiness review

Follow-up теперь оформлен как новый unchecked T115 в существующем003, без изменения113completed и полной строки uncheckedT114. [План T115](plan.md#t115--trusted-auth-первичная-ошибка-и-безопасный-caseexit) закрепляет shared Windows test-only lifecycle в25 ordinary parent bodies и отдельном orphan, actor registry.stop→reverse Pair.close и failed Pair.start. Реальный pure startup adapter использует typed holder/отдельный success flag; successful Pair и nullable null result не закрываются. Nonclient StateError сохраняет private stack; client ERROR/default exit0, client finally, прежние joins/fail-fast/70s/90s/nested bounds и native oracles не меняются. Completion barrier здесь не требуется; lifecycle actor уже удерживает stdin.

Schema1 добавляет только fixed trusted-auth-<scenario> для exact25 literals и numeric primary zero-exit в диапазоне[-2147483648..4294967295] без0 при locald phase/checked producer/current parent+actor+Windows helper+locald adapter hashes/valid suiteURL/fullname/declaration/lines. Shared OwnedFixtureFailure fields ровно primary/primaryStack/secondary/secondaryStack; primary segment ограничен exact `\nOWNED_FIXTURE_CLEANUP_FAILURE:\n` separator. Secondary/cleanup-only/PASS/orphan/foreign/stale/spoof/private output не дают exit или primary frames. Orphan не получает новый case; phase/safeCode newly identified trusted-auth-* принудительно null, с override generic legacy classifier. Все остальные old fields/bounds/privacy и3primary frames сохраняются. Это не определяет actual actor outcome/scenario/root cause CI6; delete121 тогда не был достигнут.

Подготовлены обязательные meaningful lifecycle/startup RED/GREEN, actual unchanged-oracle25+orphan, locald analyze/root exactformat/analyze/fullFluttertests/fullcontrolledPS old+new/links/diff и fresh code-spec/recording reviews. Shared helper согласуется и frozen владельцемT114; actual native runs выполняются последовательно сT11437/fullWindows. В этом spec этапе такие проверки не запускались. Новая независимая readiness проверка T115 выполняется только после strict full-spec links/diff и freeze `.local/release/review-T115-spec.json` всех пяти файлов, включая unchanged pubspec+7. До completed clean readiness review T115 code handoff не выполняется; готовность здесь не объявляется.

Metadata+7 общая дляT114/T115. Действующая private+6/sourceZIP6, cachedf1, пять прежних installs/workspace, dirtyH, unactivated c45/oldRED сохранены. До future exact commit и full cold successful CI merge/tag/source-only release запрещены; build/install/source/tag/publication требуют отдельных receipts. Binary/signing/full001/021/005 boundaries прежние.

Узкое уточнение T114 перед общим review: pending cached stdin.close не должен блокировать достижение прежнего5s child join. Child cleanup теперь инициирует/наблюдает единственный cached close→prompt owned kill до await close→ожидает close+exit в одном общем оставшемся5s monotonic budget; join предпринимается и при failure/pending close, worker.close выполняется в finally. Прежний broad catch принимает любую IOException от owned stdin.close без нового errno filter; StateError/другие non-IO ошибки сохраняются как failure. Pending-close timeout остаётся failure даже после actual child join, late ACK запрещён. Успешный body уже доказал child exit; product/runtime/operation deadlines не меняются. Нужны pure pending-close/timeout/kill/join/no-late-ACK и cleanup-only/dual-error checks. Предыдущий T114 readiness report не объявляет эти новые проверки выполненными; свежий frozen-scope review T115 охватывает также это уточнение. Checklist history сохранена, новый пакет не создаётся.

## T114/T115: фактическое локальное состояние после implementation reviews

Согласованные test-only изменения реализованы. T114 Windows Dart8 удерживает все37 client modes через bounded completion и сохраняет primary/secondary failure; child cleanup использует cached close→prompt kill→actual join в прежнем общем5s budget. T115 locald Dart4 переиспользует lifecycle в25 ordinary+orphan и actor/startup; successful Pair/null success остаётся открытым, private nonclient stack сохраняется. Diagnostics PS2 добавляет только согласованные current-source T114 phase/code и T115 case/primary exit, сохраняя schema1/privacy/bounds; для trusted-auth phase/code forced null. Production/native/provider, реальные servers и runtime contracts не изменялись.

| Текущий local check | Фактический результат |
| --- | --- |
| Meaningful unit RED/GREEN | T11431 pure passed + T1158 pure passed; original masking/uncached completion/pending close/startup RED сохранены |
| Root format/analyze/full Flutter | 639 files/0 changes;0 issues;7505 passed+1 expected opt-in capture skip/301309ms, process0/reporterSuccess=true |
| Full serial Windows | 168 passed/0 skips/242619ms/exit0, включая37 trusted-client cases и3 focused native completion tests |
| Updated oversize | 10/10 отдельных passed runs; это не reproduction actual CI6 cause |
| Trusted-auth native | 25 ordinary+orphan26 passed/0 skips/48421ms/exit0 |
| Windows/locald analyze | Оба0 issues/exit0 |
| Full isolated controlled diagnostics | 16/16 successful groups/125470ms/exit0, старые T108–T113 и новые T114/T115 source/privacy checks |
| Recording links/diff | После применения docs strict1478 total/1477 OK/0 errors/1 excluded/exit0; diff exit0; final repeat перед freeze |

Оба fresh reviews завершены0 findings: scoped Dart review на17 frozen files и отдельный PS review на19 frozen files, каждый со своими явно ограниченными conclusions и0 SHA mismatches. T114/T115 markers закрыты только для local implementation/checks/review; final recording review ещё не выполнен. Ссылки и diff после применения docs прошли; после записи этих receipts они повторяются перед freeze. Следующий gate — completed independent recording audit до commit. Полные receipts, история и ограничения — в [evidence](evidence.md); source-preservation подтверждает прежние native oracles и согласованные deadline границы.

Working+7 uncommitted; actual HEAD/private installed/source ZIP остаются+6/29c0521. Новые commit, CI7, build/install, source ZIP, tag, merge и publication ещё отсутствуют. Оба CI6 Windows RED не объявлены reproduced/fixed; cached passes не устанавливают actual actor outcome/scenario/root cause и не заменяют successful full cold CI точной будущей revision. Historical full T112 locald936/1 был до T113 и не является новым full locald run. Unqualified sourcebuilt c45 не активирован; normal private f1/пять старых versions/workspace/dirty H и completed T001–T113 сохранены. Public assets по-прежнему только source ZIP/SHA; signing/public binary/native distribution/full001/021/005 остаются открытыми boundaries.
