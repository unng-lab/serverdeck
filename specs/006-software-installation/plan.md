# План006 — чистая установка напрямую по SSH

**Дата**: 2026-11-01. [Спецификация](spec.md), [общий план001](../001-service-foundation/plan.md),
[контракт](../001-service-foundation/contracts/direct-ssh.md), [задачи](tasks.md).

## Summary и Technical Context

Flutter/Dart engine компилирует supported recipes PostgreSQL16/ClickHouse в
ограниченные direct SSH-команды. Используются существующие dartssh2/crypto/Isar
и host stock tools; server executor, Python/Ansible и standalone installer удаляются.
Target Ubuntu24.04 amd64/systemd, root/noninteractive sudo, APT metadata/sources
заранее подготовлены администратором. Отдельный backend не нужен.

## Ответственность и решения

006 владеет recipe descriptor, installation prechecks/effects/postchecks и обоими
продуктами. 001 владеет transport/locking/receipts/recovery;021 — MCP/grants/AST.
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
Factual checks обязательны для обеих программ. Unit fixtures доказывают код
выбора/проверки, а не квалификацию реального пакета или release.

## Этапы и зависимости

1. Catalog/descriptor/preflight: после typed transport и direct identity001.
2. Install/native-lock gate/config/SQL checks: после host reservation/step001.
3. Failure/cancel/unknown/parity/cleanup: через общий job driver001/021.

## Constitution Check и validation

Применяются все8принципов4.4.0 без исключений. Static/unit only; commands,
fake byte port, compiler, exact pins, signing/lock failures, SQL/settings,
NetBird/neighbor preservation и lost ACK обеих программ проверяются раздельно.
Full checks/links/independent review — по001. Реальный SSH/APT/systemd не запускать.
