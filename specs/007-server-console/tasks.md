# Tasks: Консоль сервера

**Input**: [spec](spec.md), [plan](plan.md), [data model](data-model.md), [contracts](contracts/mcp-console.md), [research](research.md).
**Tests**: Обязательные unit/fakes по FR718; tests before соответствующей implementation. Нет integration/e2e/release/layout feature gates.

## Phase 1: Setup

- [x] T001 Скопировать MIT xterm4.0.0 в third_party/xterm с LICENSE, origin/hash/PATCHES.md; добавить path dependency pubspec.yaml/pubspec.lock, проверить offline closure (FR717).
- [x] T002 [P] Дополнить scope001 документацию specs/001-design-system/component-library.md/spec.md/plan.md/tasks.md терминальным C26 и обновить docs/design/components/registry.json при реализации (FR716).

## Phase 2: Foundational

Все user stories используют эти контракты; каждый пункт содержит собственные synthetic units, не запускающие приложение.

- [x] T003 Написать test/console/terminal_engine_test.dart для fragmented UTF8/ANSI/main-alt/replies/CSI8/caps/eviction/cursor/plain-text, до реализации adapter (FR703/713/714/720/721).
- [x] T004 Реализовать bounded parser/control string/CSI limits16KiB/32params/6digits/65535, onResponse split и запрет remote resize в third_party/xterm/lib/src/core/escape/parser.dart и lib/src/terminal.dart; исправить appCursorKeys mapping (FR703/713/714).
- [x] T005 Ограничить main scrollback10000 rows/4194304 bytes incl LF, alt0scrollback/screen200rows,cols2..512 иrowspans; исправить detach/eviction/scroll rowownership в third_party/xterm/lib/src/core/buffer; test/console/terminal_engine_test.dart (FR713/720).
- [x] T006 Создать lib/console/terminal_engine.dart с единым engine/stateful decoder,16KiB processing chunks,plain-text row projection/version/cursor, без sideeffects/replies напрямую SSH (FR703/713/714/720).
- [x] T007 [P] Написать test/connections/console_pty_test.dart на synthetic SSH messages/socket для cancel/late-open/rekey/window/retiredslot/finalwrites до изменения vendor (FR702/708/709/710).
- [x] T008 Добавить guarded bounded PTY API в third_party/dartssh2/lib/src/ssh_client.dart,ssh_channel.dart и экспорт: timeout15s,receive65536/maxpacket32768,16protocolslots incl retired,late-open no shell,PTY ACK before shell/quoted custom path,onData before buffering (FR702/703/708/713).
- [x] T009 Добавить waitForKexReady/trySendPacket безrekeybuffer наfalse в third_party/dartssh2/lib/src/ssh_transport.dart,guarded upload/window waits безlegacy stdin и guarded setup/request FIFO cancellation (FR709/710/724).
- [x] T010 Добавить immediate packet admission в lib/connections/ssh_transport.dart: reserve payload+256 BEFORE encrypt,queue-empty/rekey-idle check,raw.add sync under gate,flush outsidegate/FIFOtail,no ciphertextdrop,no retry after encryption (FR709/710/724).
- [x] T011 Добавить lib/console/console_port.dart и capability в lib/connections/connection_owner.dart/ssh_transport.dart: currentbinding/fence,synchronous invalidation,independentcollectionqueue,no secondSSH (FR702/710/712).
- [x] T012 Определить explicit typed public console projections/errors в lib/console/console_models.dart и lib/domain/models.dart,shared domain actor/gate boundary; generation/revisions<=9007199254740991 (FR701/708/719).

## Phase 3: US1 — Interactive console (P1)

Independent test: AC701–704 with fake transport; one session,explicit open,correct output,trust denial.

- [x] T013 [US1] Написать test/console/console_owner_test.dart: reservation4/server16global incl ended/opening,duplicatepending,timeout15s,trustfence,input/outputcallbacks,error state; AC701–704/FR701/702/707/708.
- [x] T014 [US1] Создать lib/console/console_owner.dart/session.dart: atomic reservation,immutable shell snapshot,open outsidegate,final guards,generation/output routing,device replies same boundedFIFO (FR701/702/703/707/708/713/714).
- [x] T015 [US1] Реализовать shared C26 lib/ui/deck_terminal.dart с TerminalView/custom keyboard-paste actions,readOnly,onResize/visibility,BrandTheme и ownercallbacks; synthetic tests test_design/components/terminal_test.dart,каталог tool/component_catalog/examples.dart/registry001 (FR716).
- [x] T016 [US1] Добавить lib/console/console_view.dart: context/state/actions/terminal/closeconsent,multilineconsent exactbytes,generation guard; test/console/console_view_test.dart проверяет text/semantics/callbacks,не layout (FR701/703/709/711/716/718).
- [x] T017 [US1] Подключить console owner к lib/runtime/feature_runtime.dart/runtime_view.dart и вкладку к lib/profiles/profile_view.dart; просмотр no connect/open,selectedsession perprofile (FR701/702/712).

## Phase 4: US2 — Shell profiles/settings (P1)

Independent test: AC705–709 fake repository,default/save/restart model/CRUD/error.

- [x] T018 [US2] Написать test/console/console_settings_test.dart для nulldefault,strict JSONv1<=32KiB,max16profiles,name1–80scalars,path1–1024UTF8bytes/noNULCRLF,defaultrelation/atomicerrors/conflicts/snapshot (FR704/705/706).
- [x] T019 [US2] Создать lib/console/console_settings.dart: stableUUID/login,strictJSON,revision1null,atomic UiActor save expectedRevision/revision+1,settings/dataRevision increments,no unrelatedfieldwrites (FR704/705/706).
- [x] T020 [US2] Добавить nullable AppSettings.terminalConfiguration в lib/storage/records.dart,regenerate records.g.dart; audit readStringOrNull иmissingdefault в test/console/console_settings_test.dart без realIsar,сохранитьformat2 ипрочиеданные (FR706).
- [x] T021 [US2] Добавить lib/console/console_settings_view.dart и вкладку «Терминал» lib/runtime/application_settings_view.dart/runtime_view.dart: explicitSave,preservedDraft,CRUD/default/unavailablepathmessage; functional fake test/console/console_settings_view_test.dart (FR704/705/706/716).
- [x] T022 [US2] Связать opening snapshot/oneoffchoice с settings owner в lib/console/console_owner.dart/console_view.dart; edits/delete affect futureonly,absent customshell no fallback (FR704/705/706).

## Phase 5: US4 — Shared MCP console (P1)

Independent test: AC715–722 via router+fake owner/transport; sharedchannel/history,lease,replay,revoke.

- [x] T023 [US4] Написать test/console/console_access_test.dart для singlelease,60sexpiry/read no renewal,UI takeover,UI firstinput vs acquire,clientbusy,bindingEOF,revoke/rotation/disable,pendingcancel (FR715/722/725).
- [x] T024 [US4] Реализовать lease/binding в lib/console/console_owner.dart/session.dart и attenuation lib/domain/actor.dart либо trusted ConsoleMcpBinding: tokennotJSON,expiry/checks,takeover,partialline unchanged,no secretstoreprompts (FR715/722/723/725).
- [x] T025 [US4] Написать test/console/console_replay_test.dart для lostresponse/reconnect/sameIDdiffpayload/evicted(CONSOLE_REPLAY_EXPIRED)/highWater/oldEpoch/partialunknown/no diskpayload (FR709/724).
- [x] T026 [US4] Реализовать lib/console/console_replay.dart: max64principals,64results each,4096metadata/result,onepending,monotonic sequence/highWater,sha256payload,no plaintextcache,no reaccept evicted; opening/lease/write/close samepolicy (FR724).
- [x] T027 [US4] Реализовать typed console operations в lib/console/console_owner.dart/console_operations.dart: list/profiles/open/read/acquire/release/write/close,sharedterminal,target guards,keyencoding/no hiddenexec,confirmedMultiline (FR719/723/724).
- [x] T028 [US4] Написать test/console/console_history_test.dart и реализовать lib/console/console_history.dart: rows/UTF8scalarcursor<=512chars,current screen+main scrollback,staleVersion=>successful historyGap=true/rows=[]/nextCursor=null,1000rows/64KiB,finaltext afterended,no echooff inputhistory (FR720/721).
- [x] T029 [US4] Дополнить lib/mcp/router.dart и tool_schemas.dart: consoleoperations injection,8typedtools,connection binding close/cancel,complete frame<=1MiB incl duplicatedcontent; test/mcp/console_router_test.dart schemas/unknownkeys/grants/caps,точные historyGap-success и CONSOLE_REPLAY_EXPIRED (FR719/721/725/726).
- [x] T030 [US4] Согласованно обновить assets/mcp/tools.json и specs/003-ssh-mcp/contracts/mcp-tools.json contractVersion2/21tools,contracts/mcp.md и текущие counttests; old13 signatures неизменны (FR726).
- [x] T031 [US4] Добавить consolebinding cancellation в оба closeпути lib/mcp/pipe_adapter.dart,grantowner hook runtime; test/mcp/console_router_test.dart/test/console/console_access_test.dart дляEOF/revoke/cachedenial (FR725).
- [x] T032 [US4] Обновить UI grant descriptions lib/mcp/settings_view.dart и console view текущим MCPвладельцем/«Взять управление»/«Передать управление MCP» безобязательногоshowUI дляMCP; test/console/console_view_test.dart (FR715/722).

## Phase 6: US3 — Lifecycle/recovery (P2)

Independent test: AC710–714 fake clock/channel/runtime; noforeignclose/noautoopen/replay.

- [x] T033 [US3] Написать test/console/console_lifecycle_test.dart: switch/tray/settings/detach preserve; normaldisconnect keepsreadonly,trust/auth/delete clears;latecallback ignored;close one/sharedSSH alive;shutdown drain (FR710/711/712).
- [x] T034 [US3] Завершить lib/console/console_owner.dart и runtime capability ordering: synchronous stopadmission,opening cancellation,channelclose/drain,renderer detach only;activecloseconsent vs ended (FR710/711/712).
- [x] T035 [US3] Ограничить inputFIFO64KiB/rawqueue1MiB/15s inputwait,wholeactionreject,partialunknown,device responseguard в lib/console/session.dart/console_owner.dart; boundary/failure cases test/console/console_lifecycle_test.dart (FR709/713/714/724).

## Phase 7: Validation and convergence

- [x] T036 Выполнить dart format --output=none --set-exit-if-changed .,flutter analyze,flutter test,tools/check-test-boundaries.ps1 и flutter test test_design/components; исправить подтверждённое,сохранить реальные результаты specs/007-server-console/reviews/evidence.md (FR718/SC701–707).
- [x] T037 Выполнить lychee "specs/**/*.md",сохранить результат reviews/evidence.md; пометить недоступные исторические ссылки specs/006-install-update/reviews/main-version.md/update-restart.md как historical identifiers безподмены фактов.
- [x] T038 Провести independentread-only review freshsubagent по AGENTS.md сexactscope/checkresults,исправить findings и повторитьchecks/review; report specs/007-server-console/reviews/final.md.
- [x] T039 Выполнить speckit-converge по текущему коду,append-only tasks.md дляgaps; закрыть gaps implement/checks/freshreview;послеzero-findings обновить specstatus/reviews/evidence.md честнымscope.

## Dependencies & execution

Setup→Foundation→US1→US2→US4→US3→Validation. MVP US1 использует built-in login settings; US2 отдельно проверяется fake repository,US4 fakebinding/transport,US3 fakeowner. Shared files последовательно. Возможные независимые пары: T003/T007 tests; T018settings иT025replay tests послеfoundation; T028history unit иT030registry имеют отдельные файлы,но routerтребует оба. Метки[P] не разрешают запускreviewво времяправок reviewedfiles. Исследования/independentreviews делегированы по skill/AGENTS, implementation выполняется последовательно.

## Traceability

FR701→T012–017;702→T007–011/013–017;703→T003–006/008/014–016;704–706→T018–022;707–708→T008/013–014;709→T009–010/016/025–027/035;710→T009–011/033–035;711→T016/027/033–034;712→T011/017/033–034;713→T003–006/008/014/028/035;714→T003–006/014/024/028/035;715→T023–024/031–032;716→T002/015–017/021;717→T001/004–006;718→T003/007/013/016/018/021/023/025/028–029/033/036–038;719→T027/029;720–721→T006/028–029;722→T023–024/032;723→T024/027;724→T009–010/025–027/035;725→T023–024/029/031;726→T029–030. SC701–707 соответствуют UStests иT036. AC701–704→T013/016;705–709→T018/021;710–714→T033;715–722→T023/025/028–029.

## Increment review fixes

- [x] R701 Clamp saved cursor after shrink on main/alt buffers; synthetic engine regression.
- [x] R702 Reject zero SSH remote packet size before PTY; enforce positive fragment progress/deadline; synthetic protocol regression.
- [x] R703 Keep selected session per profile across renderer/server navigation; functional callback/state regression.

- [x] R704 Discard unfinished decoder on trust clear before parser/buffer reset; capped OSC plus incomplete UTF8 regression.


## Phase 8: Convergence

- [x] T040 Enforce creator actor/request/grant guard before each PTY setup packet and ready promotion in lib/console/console_owner.dart; synthetic cancellation/authorization races test/console/console_open_authorization_test.dart per FR-725/SC-706 (partial, HIGH).
- [x] T041 Propagate one action deadline/cancellation through packet admission/rekey/drain/flush; removable wait listeners/timers and partial outcome, preserve committed ciphertext/FIFO; lib/connections/ssh_transport.dart and third_party/dartssh2 guarded PTY, synthetic adapter units per FR-709/713/724 and plan bounded SSH (partial, HIGH).
- [x] T042 Align console_history.dart with exact named cursor object/section values in data-model.md; strict keys/types, roundtrip/cross-target/version unit cases per FR-721/SC-707 (contradicts, HIGH).
- [x] T043 Preserve stable typed PTY/shell refusal, timeout, protocol-cap and network opening reasons across console port/SSH/owner/UI; synthetic failure and UI text checks per FR-708/SC-701 (partial, HIGH).


## Phase 9: Convergence

- [x] T044 Route multiline platform/IME text edits and internal PasteTextIntent through C26 owner-mediated paste consent, preserving ordinary Enter keys; add shared synthetic input and functional console tests for pre-consent/cancel/lease/session changes per FR-709/716/SC-705 (partial, HIGH).

## Release provenance correction — 2026-11-07

- [x] T045 Refresh third_party/dartssh2/UPSTREAM.json and patches/dartssh2-4.1.0-policy.patch against the verified4.1.0 archive for reviewed console patches/owned PTY; preserve source hashes/allowlist/reverse-patch checks. Validate tools/check-ssh-vendor.py and the publishable build, mandatory checks and independent review before v0.2.1 (FR-717; release supply, bug in v0.2.0).
