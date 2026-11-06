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
- V: обычный выход через трей; явно подтверждённое обновление с перезапуском —
  узкое исключение constitution4.0.0, использующее общий безопасный shutdown.
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
in local publisher storage outside the repo with restrictive ACL; its matching copy
is configured as a repository Actions secret for tag-only automatic publication.
Initialize never rotates trust automatically. prepare-release verifies final audited
installer/resources, matching key and previous signed records before signing on the
runner. Local builds audit assets without publication.

Main-window version amendment: lib/runtime/native_platform.dart adds nullable
RuntimePlatform.release implemented from initialized local context; no guessed missing
release. RuntimeView reuses C18/C10 in C17 status for both profile and readiness paths.
Only test/runtime/fakes.dart implements the other RuntimePlatform; it receives a fake
release. Functional widget tests cover full version, unknown, storage failure/retry,
runtime rebinding and profile workspace; no shared/design/runtime protocol changes.
Version0.1.0+3 is a new immutable release; prepare-release verifies and preserves the
signed v0.1.0+2 catalog record. No schema/dependency/key/root/automatic-exit changes.

Review correction: release is a read-only ValueListenable<String?>, published at
native initialize completion independently of pending DB open; RuntimeView observes
it with ValueListenableBuilder. No new wire events/sequence values or extra calls.

## Amendment: direct update entry and safe restart

FR-621 → RuntimeView separate owned update route + UpdateView, C02/C14/C18, T083.
FR-622 → RuntimeCoordinator/RuntimePlatform typed request + native atomic UpdateService
acceptance/latch, shared cleanup and retry, T084. FR-623 → host result8,
bootstrap owner-to-maintenance transfer and dedicated restart adapter in startup_update,
T085. Tests T086 cover AC-619–620 and SC-607; full release/check/review T087.
T082 readiness precedes code; T083 and T084 may be developed independently, T085 follows
native contract, T086 validates combined behavior. Shared design scope unchanged.


## Stable SemVer migration (2026-11-06)

New release identity is `0.1.1`, then stable `major.minor.patch`; no suffixes.
The build entrypoint rejects suffixes. Host CMake reads pubspec directly because
Flutter may synthesize a build suffix. String resource/runtime identity matches
bootstrap SDBUILD001/setup/audit/catalog/tag; Windows numeric revision is0.
Python/native codecs accept only three components; old `+N` metadata/catalogs and
pending consents are unsupported. User chose a clean installation, with no migration
or compatibility layer. Database content is never implicitly cleared. No key,
store format or ABI change. See [versioning](contracts/versioning.md).


## Tag-only publication amendment

The [versioning contract](contracts/versioning.md) supersedes prior local-publisher
and no-CI-secret statements above: tag push is the only release entrypoint. The
workflow builds, signs with the existing pinned-key secret and publishes both
assets before marking latest. No publication tests or trial releases are added.
