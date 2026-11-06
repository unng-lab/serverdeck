# Подготовка GitHub Release без публикации

[GitHub contract](contracts/github-releases.md) определяет источник и формат.
Это инструкция издателю; публикация в рамках текущей задачи не выполняется.
Workflow release.yml и обычный tools/build-release.ps1 теперь собирают publishable
установщик с включённым GitHub source, используя release/update-policy.json из
репозитория. Developer-профиль доступен только явно: -Profile developer.

## Ключ и публичная настройка

Постоянная public policy schema1 закрепляет GitHub endpoint/CDN hosts, format2 и
ключ serverdeck-updates-v1. Закрытая часть хранится вне репозитория в пользовательском
LocalApplicationData/ServerDeckPublisher/keys, с ACL только SID пользователя и SYSTEM.
Она не загружается в GitHub, артефакты или логи. Первый bootstrap ключа выполняется
однократно tools/initialize-update-signing.ps1. Повтор использует тот же ключ;
потеря закрытой части при существующей public policy блокирует повторную инициализацию,
а не заменяет root. Нужна защищённая резервная копия ключа. Ротация требует заранее
доставить новый публичный ключ через доверенный выпуск согласно release contract.

## Сборка и подготовка assets

```powershell
./tools/build-release.ps1
./tools/prepare-release.ps1 -FirstRelease
```

Первая команда встраивает ту же public policy в app/setup, проверяет physical
resources/version/hash/import closure и выдаёт output/release/ServerDeckSetup.exe.
Вторая сверяет окончательные bytes с publishable audit, policy/resources, сверяет
локальный приватный ключ с публичным root, создаёт protocol2 payload и подписанный
output/release/serverdeck-update-catalog.txt. Описание берётся из
release/notes/<canonical-version>.md (UTF8≤16KiB). Оба файла готовы к размещению в
одном GitHub Release; команды сами ничего не публикуют. Workflow выдаёт однозначно
названный ServerDeck-windows-x64-update-enabled artifact с setup и public evidence;
подписать его можно локально через prepare-release.ps1 с -Installer/-Audit, соответствующими
скачанному artifact. CI не требует приватного ключа и не получает его.

Для последующих выпусков передать -PreviousCatalog <latest-signed-catalog>.
Подпись предыдущего static catalog проверяется по текущим pinned roots; прежние
11-строчные записи копируются неизменно. Первый catalog из одной записи требует явного -FirstRelease; отсутствие обоих
параметров блокирует подписание, а не молча отзывает ранее разрешённые записи.
Версии должны увеличиваться; дубль или downgrade блокируется, всего≤32 records.
Удаление старых записей требует явного решения издателя; изменять bytes старой
публикации вместо новой версии запрещено. После Authenticode/любого изменения binaries
повторить audit и подготовку metadata по окончательным bytes.

Версия 0.1.0+2 повышает build number относительно установленной developer 0.1.0+1,
чтобы полная ручная установка не была same-version byte conflict. Один раз установить
этот update-enabled setup вручную: старая unconfigured программа не может обнаружить
саму настройку источника через updater. Дальнейшие выпуски проверяются обычным путём.

## Состав релиза

Издатель создаёт stable release с tag `v<version>` (например `v0.2.0+1`), загружает
ровно один окончательный `ServerDeckSetup.exe` и `serverdeck-update-catalog.txt`,
добавляет description в body и при необходимости changelog/другие файлы в assets.
Имена обязательных assets чувствительны к регистру. GitHub size/digest после upload
должны совпасть с catalog. Публиковать latest после загрузки обоих assets;
промежуточный неполный релиз даёт отказ проверки, не успешное обновление.

Отзыв: убрать запись из fresh latest catalog либо удалить/снять с публикации
целевой release/setup. Перед применением старого consent проверяются latest
catalog и старый tag. Новый latest не переназначает target. Новый public key при
ротации заранее включается в предыдущую доверенную программу; roots из release
body/вложений не загружаются. [Проверки](quickstart.md) — synthetic unit, без
создания тестовых GitHub releases или запуска продукта.
