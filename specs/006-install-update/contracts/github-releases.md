# GitHub Releases — production source

Решение пользователя от 2026-11-04. Этот контракт заменяет произвольный metadata
endpoint, direct catalog fetch и семидневный expiry из [releases v1](releases.md).
Остальные правила подписи, identity, согласия и восстановления сохраняются.

## Источник и файлы

Единственный источник — публичные GitHub Releases `unng-lab/serverdeck`, origin
проекта. Пользователь скачивает полный `ServerDeckSetup.exe` из assets и запускает
его; setup устанавливает встроенную программу без сети. Установленная программа
проверяет GitHub REST API. Отдельного сервера DXZ/update/changelog нет. GitHub
credentials пользователя не требуются и не запрашиваются.

Production policy schema1: endpoint ровно
`https://api.github.com/repos/unng-lab/serverdeck/releases/latest`; downloadHosts
ровно `github.com`, `release-assets.githubusercontent.com`,
`objects.githubusercontent.com`, `github-releases.githubusercontent.com`.
Generic policy codec остаётся для unit fixtures; publishable packager и runtime
factory отвергают другие endpoints/hosts. Keys/storeFormat — прежние immutable
inputs; developer build без policy не обращается в сеть.

Stable release: tag `v<major.minor.patch>` (first `v0.1.1`), draft=false,
prerelease=false, published_at. GitHub latest определяет предлагаемый выпуск;
история/время asset не определяют его. Равная/меньшая версия не предлагается;
несовместимый latest даёт RELEASE_INCOMPATIBLE без выбора более старого выпуска.
Обязательны уникальные uploaded assets `ServerDeckSetup.exe` и
`serverdeck-update-catalog.txt`. Описание хранится в release body; changelog и
другие описания можно приложить файлами этого же релиза. UI согласия показывает
подписанное notes поле каталога, plain text ≤16KiB, куда издатель включает выдержку
описания/changelog. Произвольные вложения не скачиваются автоматически, Markdown/
HTML не исполняются; дополнительные файлы не обязательны для установки.

## GitHub adapter

`GitHubReleaseSource` — native/include/github_releases.h и
native/install/github_releases.cpp; bounded HTTP port отделён от parser/selection.
Production adapter WinHTTP использует OS TLS, без bypass. Latest и, когда нужно,
`/repos/unng-lab/serverdeck/releases/tags/{tag}` запрашиваются с Accept
`application/vnd.github+json`, X-GitHub-Api-Version `2026-03-10` и User-Agent
product/version/platform. API redirects запрещены. Нет Authorization, cookies,
credential fallback, install ID, скрытых retries или входа через браузер.

API response≤512KiB, assets≤128. Unknown fields игнорируются; duplicate JSON keys
и неверные типы обязательных полей отвергаются. Нужны tag_name, draft, prerelease,
published_at, assets. У обязательного asset: state=uploaded, name, size,
digest `sha256:<lowercase64hex>`, browser_download_url. Catalog size1..128KiB,
setup1..1GiB. URL HTTPS443, github.com, именно этот repo/tag/filename; без userinfo,
query, fragment, дополнительных segments. Tag decode ровно один раз; decoded tag должен быть `v<major.minor.patch>`.
Signed setup URL canonical с обычным тегом без percent-encoding.
Суффиксы `+build`/prerelease и иной repo/tag отвергаются.

Catalog asset проверяется по API size/digest, затем по embedded key/signature.
API digest не заменяет подпись. Latest tag имеет ровно одну запись в каталоге;
setup size/hash совпадают с API asset. Signed published UTC — время подготовки
выпуска, показываемое пользователю; API published_at подтверждает публикацию, но
не обязано совпадать с заранее подписанным временем. Остальные
записи не новее latest; URL каждой — setup соответствующего tag этого repo.
Предлагается только запись latest, если совместима и новее installed.

Catalog download redirects≤3, HTTPS и allowlist на каждом hop; начальный URL
обязательно соответствует repo/tag/filename. Вся проверка latest API + catalog +
optional target API имеет общий deadline30s, включая redirects/чтение, и отмену.
Лимит фактических bytes действует без Content-Length. Setup сохраняет прежние
30s/60s/30min и chunks≤64KiB. HTTP non-200 (включая 403/429 rate limit и 404 latest)
даёт NETWORK_UNAVAILABLE; invalid JSON/catalog — INVALID_CATALOG; изменённые identity
bytes — SOURCE_CHANGED. 404 latest не означает «актуально». Ошибка сохраняет
lastSuccess/consent/готовый setup. Нет hidden retry; обычные manual/24h правила.
UI не показывает HTTP body, credentials или произвольные URLs.

## Подписанный static catalog protocol2

Envelope `SDCATALOG002\n<keyId>\n<signatureHex128>\n<payload>`.
Payload `SDRELEASES002\n<issuedUTCseconds>\n<count>\n`, затем прежние 11 строк на
release и [codec limits](releases.md#catalog-codec). issued≤now+300s;
published≤issued; expiry поля нет. Редкий выпуск не требует еженедельной подписи.
Protocol1 остаётся legacy codec/unit coverage; production GitHub source принимает
только2. Catalog хранит protocol; expires для2 отсутствует (native representation0).
Pending хранит exact signed bytes и verifiedAt; restore проверяет подпись на
original verifiedAt без сети, но это не разрешает offline apply.

Каталог latest содержит latest и ранее разрешённые неизменённые записи, всего≤32.
Издатель переносит записи старых версий, согласие на которые ещё действительно.
Удалённая запись означает RELEASE_REVOKED; изменённая identity той же версии —
SOURCE_CHANGED. Новый latest не меняет подтверждённый target.

Перед применением нужны fresh latest API + fresh catalog.
`CatalogSource::FetchFor(consented,cancel)` проверяет наличие и identity target.
Для target, отличного от latest, дополнительно fresh release-by-tag API:
published stable status, exact tag, uploaded setup size/hash/url. Target404,
draft/prerelease или отсутствующий setup — RELEASE_REVOKED; изменённые bytes —
SOURCE_CHANGED. Сеть не равна отзыву. Fake/legacy FetchFor может делегировать Fetch;
production обязана проверять target. Старый сохранённый каталог недостаточен.

## Поставка и проверка

App с policy → окончательный setup → protocol2 catalog с final hashes → оператор
размещает assets/body в GitHub Release. Tag/URL известны до upload, asset IDs не
подписываются: циклической зависимости нет. Signer поддерживает protocol2 и legacy1;
publishable packaging проверяет GitHub policy. Публикация сейчас не выполняется.

FR-618/AC-616 → этот контракт → T055–T057 в [tasks](../tasks.md). Unit fixtures:
API headers/URL, stable selection, tags, assets, size/digest/signature mismatch,
protocol2 спустя неделю, rate limit, cancel/deadline/redirects, новый latest со
старым consent, удалённый/изменённый target. Только synthetic HTTP, без live network,
product launch или integration gates.

Официальный контракт:
[GitHub Releases REST](https://docs.github.com/en/rest/releases/releases),
[GitHub assets REST](https://docs.github.com/en/rest/releases/assets).
