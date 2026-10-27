# UI contract and acceptance — 001.1

[Plan](../plan.md), [API](local-api.md), существующий [brandbook](../../../docs/brandbook/README.md). Использовать обе темы из tokens и Noto fonts с OFL. Источники/ассеты брендбука не изменяются; шрифты подключаются в новый pubspec.

## Оболочка

Пять разделов: Серверы, ПО, Журналы, Задания, Настройки. Первый экран — Серверы. Будущие разделы показывают пустоту и причину недоступности, без demo и вымышленных чисел. Подключение недоступно до 001.2, задания — до 001.3/006. В header видны имя и адрес выбранного профиля; локальный выбор не означает подтверждённое SSH-доверие. Удаление последнего профиля оставляет пустую модель и null selection.

До ready приватные данные не отображаются. Starting/recovering показывают ограниченное ожидание; blocked/incompatible/unavailable — безопасную причину и ручной retry. Отказ locald не называется «Сервер выключен». Профили доступны offline без аккаунта; удалённое состояние — «Не подключён / функция недоступна», а не fake healthy. Snapshot другого окна не переписывает draft. CAS conflict показывает изменение другим окном и предлагает reload/cancel; draft хранится только в RAM до выбора пользователя.

## Профили, credentials и настройки

Форма содержит name/address/port22/SSH user/tags и mode none/password/privateKey с validation из data-model. Existing secret не возвращается для показа. Reveal разрешён только для введённого transient input. Private key вставляется либо читается picker из явно выбранного файла ≤64 KiB в RAM; путь не сохраняется/не отправляется locald. Не брать implicit ~/.ssh. Keep/replace/remove явно соответствуют действиям формы.

Save атомарно сохраняет профиль и credential, не подключает сервер. Cancel ничего не пишет. Delete требует confirmation с name/address: «Удаляется локальный профиль; сервер не меняется». Spinner не блокирует навигацию или другое окно. Повтор save сохраняет requestId. Success — только commit и перечитывание, failure не показывает optimistic success. Потерянный reply означает неподтверждённое сохранение; проверить результат тем же id. При UI restart сначала model/recent, без auto-save прежней формы. Credentials не сохраняются в UI preferences; clipboard автоматически не меняется.

Настройки theme system/light/dark и reduceMotion сохраняются через CAS API, не UI-owned DB. Raw export недоступен; стандартная диагностика содержит только safe allowlist. Намеренный приватный экспорт вне 001.1.

## Accessibility

Обе темы используют brand tokens; focus видим, touch targets ≥48 logical px, состояния имеют текстовые подписи. Tab/ShiftTab, Enter для валидной формы, Esc для cancel/close; Esc не отменяет уже committed action. После закрытия dialog focus возвращается инициатору. При width ≤800 logical px drawer вместо rail, формы прокручиваются вертикально. 360×800/390×800 — Windows viewport tests, не объявление Android runtime. На 1100×760/800×600 и text scale200% основные действия доступны и не перекрыты. NotoSans — UI, NotoSansMono — технический текст, лого/ICO соблюдают brand minimum.

## Acceptance mapping

### Независимая подготовка pre-ready view T088

После принятой подготовки тем T087 допускается отдельный typed presentation component для всех non-ready состояний LocalAPI. Вход: ReadinessState кроме ready, nullable safe ErrorCode, nullable retry callback и retryInProgress default false. Ready не поддерживается этим компонентом и отвергается; private model/сервисные операции в нём отсутствуют. Starting/recovering не получают ручного retry; stopping показывает завершение. Для storageBlocked/incompatible/unavailable callback означает наличие реального владельца retry; без callback кнопка отсутствует, при pending она disabled и сообщает об ожидании. Auto-retry и readiness watchdog не реализуются в view: их владелец T031.

Reason отображается исключительно через локализованную ErrorCode allowlist, без raw exception/private input; safe default unavailable сохраняет текущий текст о нереализованной локальной службе. Полный список пяти разделов, данные и интеграция остаются T034/T031. Прокрутка, textscale200%, обе темы/four viewports, 48logicalpx retry и keyboard focus/activation проверяют только этот компонент, не закрывают полную Q12. Подготовка не выполняет отложенные native/encryption checks и не меняет обязательные зависимости полной001.1.

Все Q в [quickstart](../quickstart.md) — будущие проверки, не evidence.

| AC | Design/check |
| --- | --- |
| AC-SVC-1A | Client/locald, пустое защищённое пространство, CRUD/restart offline: Q01/Q02/Q05/Q09 |
| AC-SVC-1B | Профиль и credential link восстанавливаются после reopen; обычные metadata читаемы в базе, секретные markers отсутствуют открыто: Q05/Q08/Q09; отказ защиты Q06 |
| AC-SVC-1C | Два окна, CAS и lost reply дают один эффект: Q07/Q10 |
| AC-SVC-BOOT | Key/corruption/version fail closed: Q06/Q08/Q11 |
| AC-002-1A | Delete all без demo, save failure не success: Q09/Q08 |
| AC-002-1B | Denied/unsupported видны без эффектов: Q04/Q11/Q12 |
| AC-002-1C | Сохранение контекста/данных при прерывании: Q07/Q08/Q10 |

PEM input detail T169: скрытое поле приватного ключа доступно только для просмотра, с подсказкой включить показ для ручного ввода либо выбрать файл. Явный показ открывает multiline editor, сохраняющий LF/CRLF без преобразований; повторное скрытие сохраняет исходное значение. Выбор файла не требует показа ключа. Это предотвращает удаление LF стандартным obscured single-line editor Flutter; пароль/passphrase сохраняют single-line validation без управляющих символов.
Runtime UI framework/unhandled diagnostic faults use the separate [runtime diagnostic contract](runtime-diagnostics.md). It governs ordinary error output and last-resort error rendering, without changing typed locald readiness, credential input, mutation/conflict/recovery or domain validation contracts. File scans alone do not establish this runtime guard; T231 requires distinct fault acceptance.
