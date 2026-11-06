# Implementation Plan: Установка и обновление

**Branch**: `006-install-update` | **Date**: 2026-11-04 | **Spec**: [spec.md](spec.md)

## Summary

Полный native `ServerDeckSetup.exe` устанавливает самодостаточный `ServerDeck.exe`.
Native maintenance обслуживает файлы/регистрацию без Isar/SSH/MCP. Bootstrap проверяет
pending до runtime; transient setup заменяет EXE после освобождения образа bootstrap.
UI обновлений переиспользует готовые компоненты 001 и native update port.

## Technical Context

- **Language/Version**: C++17 MSVC v143 x64; Flutter3.47.7/Dart3.13.5; Python3.12+,
  PowerShell7 для build/sign tooling. Дополнительного installer framework нет.
- **Primary Dependencies**: существующие security/payload/instance; штатные WinHTTP,
  BCrypt, Known Folders, IShellLink, HKCU. Native bootstrap/setup `/MT`.
- **Storage**: bounded служебные файлы, не новая Isar schema и не отдельный store owner.
- **Testing**: unit/widget fakes, native unit с synthetic ports/temp files, Python unit.
- **Target Platform**: Windows10/11x64, обычный пользователь, несколько logon sessions/SID.
- **Performance Goals**: одна maintenance операция/SID, bounded IO по контрактам;
  сеть не блокирует window thread.
- **Constraints**: без admin/service/force-kill, e2e/VM/smoke/process-kill/design tests.
- **Scale/Scope**: одна установка/SID, один stable-канал, catalog≤32 releases, keys≤3.

## Constitution Check

- I: C02/C04/C10/C11/C12/C14/C18/C23/C27/C28 в UI; native setup использует стандартные
  Windows confirmation/error dialogs до Flutter. Новых reusable UI нет.
- II/III: только unit/fake/static/build; никакого запуска продукта/реальной Isar из тестов.
- IV: синхронизирован по пользовательскому решению installer → installed EXE;
  transient maintenance не открывает бизнес-данные и не является фоновой службой.
- V: работающий owner завершается только пользователем через трей. Startup handoff
  до host не является альтернативным выходом из UI.
- VI: сохранение данных, без искусственного format bump/migration/reset.
- Post-design gate: те же ограничения закреплены в контрактах и задачах.

## Project Structure

Документы: [research](research.md), [data model](data-model.md),
[installation](contracts/installation.md), [releases](contracts/releases.md),
[platform](contracts/platform.md), [quickstart](quickstart.md), tasks/checklists/reviews.

```text
native/include/{installation,release_catalog,update_service}.h
native/install/{installation,release_catalog,update_service}.cpp
native/include/artifact_transfer.h
native/install/artifact_transfer.cpp
native/include/pending_update.h
native/install/pending_update.cpp
native/include/{install_executor,install_registration,setup_package}.h
native/install/{install_executor,install_registration,setup_package}.cpp
native/installer/main.cpp
native/bootstrap/main.cpp
native/tests/{installation,release_catalog,update_service}_test.cpp
native/tests/install_executor_test.cpp
native/CMakeLists.txt
windows/runner/{CMakeLists.txt,platform_channel.cpp,platform_channel.h}
lib/updates/{update_owner,update_view}.dart
lib/runtime/{feature_runtime,runtime_view,native_platform}.dart
test/updates/{update_owner,update_view}_test.dart
tools/{package-installer.py,sign-update-catalog.ps1,build-release.ps1}
tools/tests/test_package_installer.py
```

**Structure Decision**: codecs/state отделены от native network/file/process ports;
одна реализация для setup/bootstrap/host. Channel не даёт произвольные URL/пути/shell.
Artifact transfer streams verified setup bytes through a private sink; it does not
publish readiness or consent. Its fake request port tests per-hop policy and resource
limits independently of the WinHTTP adapter, pending storage and service wiring.
Pending publication uses two bounded fixed slots and one atomic consent pointer per
the installation contract, preserving prior readiness until the replacement commits.

## Delivery and environment

Native entry orchestration is `native/include/startup_update.h` and
`native/install/startup_update.cpp`, called by bootstrap/installer main. Shared
build/policy resource readers are build_identity.h/.cpp. SERVERDECK_BUILD_V1 binds
the mapped bootstrap version to setup metadata and prevents using an old payload
after recovery. Current handoff uses five inherited objects, including a child
read-only parent-permit Event to reject late readiness after fallback. Lifecycle
adapters remain pending_lifecycle.cpp; their invocation latch belongs to bootstrap,
outside its startup retry loop. Cache failures cannot bypass canonical verification.

Global settings compose updates/MCP in
`lib/runtime/application_settings_view.dart` with shared DeckTabs and the existing
OwnedSettingsRoute. FeatureRuntime registers UpdateOwner before startup;
RuntimeView starts it after acceptsOperations and keeps scheduling while hidden
to tray. NativeUpdatePort implements lifecycle stop/drain in addition to update
commands; 25ms nonblocking polling bridges TryDrain to the existing coordinator
shutdown budget/retry. Pending prompts retire with the settings owner. Native
channel fixtures verify epoch/args before lazy factory, cleanup without creation,
stopped admission and signed metadata/privacy mapping (T013/T015/T016/T029).

Уточнение → sync → research/design → checklist/tasks → read-only analyze → link check
и независимое design review → implement → обязательные проверки → независимый
implementation review/fix loop → converge → completion audit. Issues/publish/deploy нет.

Developer build без update policy явно показывает UPDATE_NOT_CONFIGURED и не обращается
в сеть; это не publishable release. Publishable build требует endpoint/allowed hosts,
public keys и подпись release metadata; не подменяет их демонстрационным trust root.
Значения — build environment input, не UI/MCP. Ключи закрытой подписи не попадают
в ресурсы/логи/репозиторий. Конкретный hosting/provisioning/publishing вне scope;
интерфейсы и обязательные inputs определены контрактом releases.

## Traceability

### GitHub amendment — 2026-11-04

Hosting выбран: только GitHub Releases `unng-lab/serverdeck`; прежнее исключение
hosting из scope отменено, выполнение публикации остаётся вне scope.
[GitHub contract](contracts/github-releases.md) заменяет direct fetch/expiry7days
на latest API + signed protocol2 asset + fresh target revalidation. Новый native
source/HTTP port подключается к UpdateService/runtime factory; Pending сохраняет
exact bytes, CatalogSource получает FetchFor. Signer/packager/build проверяют
protocol2 и GitHub-only production policy. T055–T057 дополняют выполненные задачи.

| Requirements / acceptance | Design / unit coverage |
| --- | --- |
| FR-601–604; AC-601–604; SC-601 | setup resource, per-user paths, registration/rollback |
| FR-605–610; AC-605–608; SC-602 | signed catalog, bounded IO, schedule/consent/cancel |
| FR-611–613; AC-609–612; SC-603–604 | leases, handoff, atomic replace/recovery |
| FR-614–615; AC-613–615; SC-605 | bounded uninstall, data retention, stable MCP path |
| FR-616–617 | network privacy and functional UI state/actions |
| FR-618; AC-616 | GitHub latest/assets, protocol2, fresh target validation |

Uninstall adapters: native/install/uninstall.cpp executes the closed removal manifest
under both leases; uninstall_cache.cpp owns bounded SDREMOVE001 marker/copy validation.
The setup entry point selects initial retained-image handoff or explicit marked retry.
WindowsRegistration projects the durable temp-helper retry command before removal.
Commit-hash binding prevents replay against an equal-version reinstall.

Pre-runtime update presentation: typed MaintenanceReporter in startup_update;
native/installer/status_window.cpp owns standard Win32 controls on a separate
message-loop thread. It has no business owner or quit/restart action. Functional
units assert revalidating/applying/recovering stages, without window/layout tests.

Release enablement amendment: release/update-policy.json is a persistent public root,
not a runtime user setting. Default build/workflow is publishable. Private key remains
in local publisher storage outside the repo with restrictive ACL; initialize tool
never rotates deployed trust automatically. prepare-release verifies final audited
installer/resources, matching key and previous signed records before local signing.
No private CI secret upload or release publication is needed for building; publishing
prepared public assets remains a distinct authorized operator action.
