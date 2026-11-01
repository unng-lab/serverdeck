# План006 — чистая установка напрямую по SSH

## Область приложений

[FR-006-APP-01–03 / AC-APP-01–04](contracts/application-scope.md) имеют приоритет
над ограничением каталогом двух БД. APT DB-specific enum/ресурсы остаются только
в схемах конкретных рецептов, не являются глобальным enum приложений.
Каталог проверяет совместимость и наличие зарегистрированного рецепта;
имя продукта используется для отображения. Новый рецепт подключается через
те же catalog/compiler/job owners с собственной проверенной схемой/ресурсами/
postchecks, без обхода текущих decoder/authority gates. Новый способ установки
требует своего контракта до реализации и не входит в эту документальную поправку.
T026–T028 связывают уточнение с приёмкой существующей APT-ветки T001–T008.
Готовность независимого способа не требует квалификации обеих БД.

**Дата**: 2026-11-01. [Спецификация](spec.md), [общий план001](../001-service-foundation/plan.md),
[контракт](../001-service-foundation/contracts/direct-ssh.md), [задачи](tasks.md).

## Summary и Technical Context APT-ветки

Flutter/Dart engine компилирует поддержанные рецепты приложений в
ограниченные direct SSH-команды. Используются существующие dartssh2/crypto/Isar
и host stock tools; server executor, Python/Ansible и standalone installer удаляются.
Target Ubuntu24.04 amd64/systemd, root/noninteractive sudo, APT metadata/sources
заранее подготовлены администратором. Отдельный backend не нужен.

## Ответственность и решения APT-ветки

006 владеет recipe descriptor и installation prechecks/effects/postchecks.
PostgreSQL16/ClickHouse — первые конкретные APT-рецепты. 001 владеет transport/locking/receipts/recovery;021 — MCP/grants/AST.
Нового хранилища, очереди, SSH pool или пути UI→SSH не создаётся.

В engine `remote/direct_ssh_catalog.dart` каталог строится read-only из exact
trusted metadata. В `remote/direct_ssh_install.dart` фиксированы проверка pins,
native APT gate, начальная конфигурация, службы, версии и SQL/effective checks.
`automation/compiler.dart` связывает recipe digest с plan effects/checks.
Публичный API не принимает package manager arguments, пути, SQL или shell.

Перед admission проверяется полная dependency closure и отсутствие существующих
product/data/config; simulated transaction только install-only additions.
Native APT hook — одноразовый root-owned input текущей попытки, полученный из
compiler, не установленный executable. Он проверяет exact package set/versions/
hashes, текущий baseline и NetBird под штатной APT frontend lock до dpkg.
Доступность native hook protocol3 — проверяемый prerequisite, без обхода lock.
Конфликт/held/постороннее обновление/удаление/downgrade запрещены. Нет apt update,
подготовки sources/keyrings и автоматического repair.

Autostart предотвращается fixed transient policy-rc.d101 guard в native APT
hook boundary по общему контракту. Existing чужая policy не перезаписывается;
created/reused custody и crash-cleanup указаны в плане/receipt. Initial auth/
loopback/settings пишутся и проверяются до явного старта службы. Неизвестные
package maintainer scripts не объявляются qualified только по APT signature.

Descriptor фиксирует exact package/archive/index/source/signature evidence;
initial settings и bounds заданы общим контрактом. PostgreSQL требует major16,
ClickHouse — совпадающих exact vendor versions server/client/common-static и
SSE4.2. Пакеты должны принадлежать supported recipe shape; неподтверждённый
candidate показывается недоступным, а не квалифицированным только по наличию в APT.
Factual checks обязательны для выбранного рецепта; SQL — для DB-примеров. Unit fixtures доказывают код
выбора/проверки, а не квалификацию реального пакета или release.

## Этапы и зависимости APT-ветки

1. Catalog/descriptor/preflight: после typed transport и direct identity001.
2. Install/native-lock gate/config/SQL checks: после host reservation/step001.
3. Failure/cancel/unknown/parity/cleanup: через общий job driver001/021.

## Constitution Check и validation

Применяются все8принципов4.4.0 без исключений. Static/unit only; commands,
fake byte port, compiler, exact pins, signing/lock failures, SQL/settings,
NetBird/neighbor preservation и lost ACK проверяются по выбранному рецепту;
обе DB fixtures сохраняются для первых APT-рецептов; независимый поддержанный
способ проверяется отдельно по своему контракту.
Full checks/links/independent review — по001. Реальный SSH/APT/systemd не запускать.

## UI-компоненты и приёмка (003.4)

[UI-раздел спецификации](spec.md) обязателен для следующих UI-задач этого пакета; [общий контракт](../003-design-system/contracts/feature-adoption.md) задаёт интеграцию. Presentation остаётся в существующих feature adapters `lib/`, переиспользует `lib/ui/deck_components.dart`, `BrandTheme` и допустимые стандартные Material controls. Catalog/demo owners не импортируются в runtime.

Для каждой композиции зафиксировать C ID/вариант, существующий owner/controller и его данные/callbacks, применимые состояния, границу identity/readiness и критерий AC-UI-006-01–03. Сохранение sort/query/selection/draft при theme/resize локально; смена цели/отзыв/утрата готовности обрабатываются действующим owner. Permission/retry/recovery/store/SSH и их лимиты остаются в сервисных контрактах, без новых UI-side owners.

Если существующего варианта недостаточно, сначала расширить каталог/контракт 003 с проверкой reuse, затем подключить его. Этим дополнением не создаются новые endpoints, схемы/миграции, зависимости или runtime actions. Новые поля передаются через действующие модели только в рамках предметных требований пакета. Текущий ограниченный validation gate сохраняется; UI/native qualification выполняется только в соответствующем разрешённом этапе, его pending-статус не означает прохождение проверки.
