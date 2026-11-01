# Embedded engine: данные и безопасный отказ

Текущая Windows-реализация открывает существующий ServerDeckNext schema3/storage
format3 напрямую. Это инструкция по исходникам, а не результат native запуска.
Нормативный [контракт сохранения](../../specs/001-service-foundation/contracts/embedded-migration.md)
и [Tasks001](../../specs/001-service-foundation/tasks.md) определяют приёмку.

## Что сохраняется

Фиксированный workspace находится в
`%LOCALAPPDATA%/ServerDeckNext/v1/workspaces/default`. Путь, owner SID, OS-user
protection, manifest, receipt-key wrapper и credential entropy bindings остаются
прежними. Смена архитектуры не требует ротации ключей или смены storage schema.
Format4 Windows-комплекта не означает format4 хранилища.

Сохраняются все16 коллекций: workspace, settings, server profiles, credentials,
foundation receipts, host trust, MCP grants, delegations, automation profiles,
revisions, plans, approvals, jobs, desired state, events и automation receipts.
Сохраняются native IDs, UUIDs, revisions, secret wrappers, expiry/revocation и
связи согласий с заданиями. Подписанный executor enrollment и защищённые MCP
credential artifacts также сохраняются. История согласия не становится новым
разрешением на исполнение.

При повторном запуске runtime sessions/challenges и одноразовые Root permits
не восстанавливаются. Отправленная незавершённая попытка получает unknown по
действующим recovery-правилам, без автоматического submit/replay. Наблюдения
теряют свежесть; SSH требует явного подключения, спорный результат — явной
сверки. Ready не означает сеть, доверенный новый host key или разрешение эффекта.

## Когда открытие запрещено

До writable open проверяются текущий runtime, owner/lease, vault/key custody,
защищённые пути и target schema3 graph. Один workspace имеет одного writer.
При занятом ownership используется `WORKSPACE_IN_USE`: этот экземпляр не
открывает второй store. Используйте уже работающее приложение; другой процесс
не завершается автоматически. При неподтверждённом закрытии владение не
освобождается ради нового запуска.

Схемы1/2/unknown и старые migration/upgrade residues не поддерживаются. Безопасные
категории отказа — `INCOMPATIBLE`/`STORAGE_BLOCKED` в зависимости от причины.
Отсутствующий, locked или повреждённый vault не считается новым workspace.
Некорректные manifest/key/credentials/ссылки графа не исправляются удалением
данных. Исходные несовместимые файлы остаются нетронутыми; нет автоматических
reset, downgrade, migration, rollback или plaintext export/import обхода.

Новый workspace создаётся только при доказанном отсутствии прежних файлов через
фиксированный атомарный schema3 initialization staging. Обнаружение неизвестного
формата не разрешает создать пустую замену. Не удаляйте lock, wrapper или
workspace вручную, чтобы обойти отказ: это не предусмотренный recovery-путь.

## Подтверждённый scope

T325 проверяет полный непустой16-family graph: действительные сервисы создают
успешное задание с consumed approval и делегирование; действительные loader и
factory повторно открывают RAM bytes. Сравниваются все raw rows и защищённые
файлы; проверяются новая session generation, fresh HMAC и receipt replay без
нового Root эффекта. Отказы native IDs, schemas1/2/99, credential reference и key
wrapper сохраняют вход. Другие custody/writer/close/recovery случаи покрыты
соответствующими действующими unit suites.

Это synthetic/RAM и static evidence. Настоящие DPAPI/ACL/Isar/filesystem,
аварийное завершение процесса и установленный комплект здесь не проверялись.
Точные команды, результаты и ограничения находятся в Tasks001; platform/release
readiness из этих тестов не следует.
