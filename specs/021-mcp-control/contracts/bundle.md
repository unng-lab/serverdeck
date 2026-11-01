# Embedded bundle and retained application identity

Действующая поправка001/021: [host](embedded-host.md),
[основа](../../001-service-foundation/contracts/embedded-engine.md),
[wire](mcp.md), [loading](loading.md), [plan](../plan.md), [tasks](../tasks.md).
Прежние format1/2/3 bundle parsers/filename-role maps не сохраняются; их история
и evidence остаются в tasks, но не являются действующим runtime контрактом.

## Closed current manifest

Единственный parser в protocol/build_manifest.dart — EmbeddedBuildManifest.
foundation.manifest.json имеет точные поля format/product/buildId/configuration/
testOnly/appRoot/apiMajor/apiMinor/workspaceSchema/sha256. Значения: integer4,
serverdeck-next, lowercase40hex+Debug|Release+lowercase64hex, matching configuration,
normal false, bounded nonempty no-NUL root, integer1/1/3. sha256 содержит ровно
serverdeck.exe и libisar.dll, плюс optional executor-release.json. Текущий build
entry генерирует descriptor и включает его hash. Никаких locald.exe/mcp.exe,
caller role maps, unknown fields, path aliases, schema/version selection или
автоматического fallback. Hashes — lowercase64hex, сохраняются immutable;
export возвращает копию. Integer values не могут быть doubles. UTF8 metadata
ограничены16KiB; malformed Unicode/non-JSON отвергаются без input в ошибке.

Удалены BuildManifest, McpBuildManifest, TrustedBuildManifest и их приватный
переключаемый fields helper. Наличие несовместимой metadata не разрешает её
переписать, повысить версию или создать новый store поверх старого. Целевые
schema3 workspace и format3 credentials/handshake сохраняются без изменений.

## Bundle and retained peer

Windows EmbeddedBuildBundle проверяет actual native prerequisites, absolute
normalized local root, plain paths, strict bounded duplicate-safe manifest и
actual hashes. Metadata/hash сами по себе не дают authority. Оригинальные bytes
manifest, bundle identity и retained process PID/SID/image/path/hash/creation
revalidate до binding и публикации. Идентичный image вне verified root не подходит;
DLL и произвольный process-supplied PID не дают peer proof. IO/prerequisite failure
не экспортирует provider text/paths; нет ремонта или скачивания runtime.

Main app и stdio connector — один image serverdeck.exe. Filename не определяет
owner/MCP role. Owner authority существует только как private app-worker capability.
Публичный native endpoint принимает лишь authenticated MCP role по format3/API1.1
handshake, descriptor2/generation и protected grant lifecycle. Коннектор проверяет
retained фактический main-app peer из descriptor и не запускает app. Grantless
mode всё равно требует живое app, не создаёт независимый сервер или owner доступ.

## Physical channel lifecycle

Production transport — EmbeddedPipeListener/Channel и McpEndpointPool. Native
attempt принадлежит своему owner до завершения, включая late bind/accept/proof/
read/write/close. Ready publication только после всех8 ordered slot bindings,
readback/proofs и final current Host check. Нельзя переиспользовать slot до
подтверждённого физического закрытия предыдущего peer/listener. Ошибка close
не превращается в idle; quarantine/CloseBlocked удерживают lease. Lease и
publication fencing не освобождаются из-за логического timeout/cancel interest.
After-await обработчики не могут оживить устаревшую incarnation/generation.
Точные state/deadline/quota/ownership решения — в embedded contracts; старые
operational NativePipe owner-role methods и test factories не восстанавливаются.

## Acceptance and limits

RAM units проверяют closed manifest4, отказ старых format/schema, immutable
hashes, strict target format3 readiness/response/error capture, native-policy
fakes, session/epoch/late ownership и физические ACK через scripted peers.
Native ABI/DPAPI/ACL/pipes/process/FS/loader/CRT/Isar/UI/build/install проверки
не выполняются в этой задаче. Старые native/teardown harness удалены; их зелёные
журналы не приёмка новой реализации. Нужны текущие full static/RAM/link checks и
независимый AGENTS.md review/fix loop с явным scope. Общая T276/goal readiness
не выводится только из удаления устаревших parsers.
