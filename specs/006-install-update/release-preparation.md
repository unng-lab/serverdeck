# Подготовка GitHub Release без публикации

[GitHub contract](contracts/github-releases.md) определяет источник и формат.
Это инструкция издателю; публикация в рамках текущей задачи не выполняется.
Workflow release.yml собирает developer artifact, не production release.

## Сборка

Public policy schema1: endpoint
`https://api.github.com/repos/unng-lab/serverdeck/releases/latest`, четыре
downloadHosts из контракта, актуальный storeFormat и настоящие public P256 keys.
Закрытый ключ хранится вне репозитория; demo root не создаётся.
`./tools/build-release.ps1 -Profile publishable -UpdatePolicy <public-policy.json>`
проверяет источник до сборки, встраивает одинаковую policy в app/setup и выдаёт
`output/release/ServerDeckSetup.exe` и `output/release-evidence/setup-audit.json`.
Policy/audit не нужны как runtime assets. После любого изменения binaries,
включая Authenticode, повторить final resource/identity audit командами build-release
до подготовки catalog. Catalog должен хешировать окончательные bytes.

## Payload первого выпуска

Этот PowerShell создаёт только локальный unsigned payload по publishable audit;
сеть/публикация не выполняются. Заменить notes кратким описанием изменений.

```powershell
$audit = Get-Content -Raw output/release-evidence/setup-audit.json | ConvertFrom-Json
if ($audit.profile -ne 'publishable') { throw 'Publishable audit required' }
$setup = Get-Item -LiteralPath output/release/ServerDeckSetup.exe
if ($setup.Length -ne $audit.setup.size -or
    (Get-FileHash -LiteralPath $setup.FullName -Algorithm SHA256).Hash.ToLowerInvariant() -ne $audit.setup.sha256) {
    throw 'Final setup differs from audit'
}
$policy = Get-Content -Raw output/release-evidence/trust-policy.json | ConvertFrom-Json
$issued = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$notes = 'Краткое описание изменений выпуска'
$notesBytes = [Text.Encoding]::UTF8.GetBytes($notes)
if ($notesBytes.Length -gt 16384 -or $notes.Contains([char]0)) { throw 'Invalid release notes' }
$tag = 'v' + $audit.version.Replace('+', '%2B')
$fields = @('SDRELEASES002', "$issued", '1', $audit.version, 'windows-x64', '1',
    "$($policy.storeFormat)", "$issued", "$($audit.setup.size)", $audit.setup.sha256,
    "$($audit.application.size)", $audit.application.sha256,
    "https://github.com/unng-lab/serverdeck/releases/download/$tag/ServerDeckSetup.exe",
    [Convert]::ToBase64String($notesBytes))
[IO.File]::WriteAllBytes('output/release/update-payload.txt',
    [Text.Encoding]::ASCII.GetBytes(($fields -join "`n") + "`n"))
```

Для следующих выпусков переносить неизменённые 11-строчные записи ранее
разрешённых версий и увеличивать count, максимум32. Header/issued/count относятся
к новому payload, старый envelope/signature не переносятся. Удаление записи
намеренно отзывает старое согласие, даже если setup остался в GitHub. Не менять
identity/bytes старой версии; исправление требует новой версии/tag.

Подписать `tools/sign-update-catalog.ps1` с параметрами `-Payload`, `-PrivateKey`
(локальный PEM путь из environment/secret store), `-KeyId` из policy и
`-Catalog output/release/serverdeck-update-catalog.txt`. Tool проверяет
keyId/P256/P1363/envelope bounds, не выводит ключ или его путь. Полное содержимое
каталога дополнительно проверяет native verifier при получении.

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
