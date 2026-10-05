# Установка и обновления ServerDeck

Windows и macOS — основные платформы. Ubuntu Desktop amd64 и Android через RuStore включены в сборку. Исходники не нужны для установки готового пакета.

| Платформа | Пакет | Установка / обновление |
| --- | --- | --- |
| Windows 10/11 x64 | ServerDeck-версия-windows-x64.msi | Установщик для текущего пользователя, ярлык меню Пуск, удаление через настройки Windows |
| macOS 12+ Intel | ServerDeck-версия-macos-x64.dmg | Открыть DMG, скопировать ServerDeck.app в Applications; при обновлении заменить приложение |
| macOS 12+ Apple Silicon | ServerDeck-версия-macos-arm64.dmg | Аналогично, отдельная нативная сборка |
| Ubuntu Desktop 24.04 amd64 | ServerDeck-версия-linux-x64.deb | `sudo apt install ./ServerDeck-версия-linux-x64.deb`; последующие пакеты обновляют установленный |
| Android 7+ | APK для RuStore | Установить и обновлять через RuStore; APK с постоянной подписью загружает издатель |

## Проверка обновлений

В верхней панели — кнопка обновлений. Она показывает установленную версию, результат проверки и доступную новую версию. Автопроверка происходит при запуске и каждые шесть часов, пока приложение открыто; её можно отключить. Ручная проверка работает независимо. Уведомление — отметка на кнопке внутри приложения.

Desktop проверяет последний стабильный релиз `unng-lab/serverdeck` и `serverdeck-update.json`. Нет опубликованного релиза — отдельное состояние; ошибки сети не означают, что установлена последняя версия. Только более новая совместимая версия предлагается к загрузке. Файл проверяется по размеру и SHA-256, затем отдельная кнопка открывает установщик. Перед открытием desktop-установщика локальный сервис корректно закрывает соединения/базу; активные или неопределённые задания блокируют остановку. Если установка отменена, перезапустите ServerDeck для возобновления сервиса. Открытие установщика не считается успешным обновлением.

macOS: завершите ServerDeck перед заменой приложения. Ubuntu: если система не открывает DEB по клику, скопируйте отображаемый путь и выполните `sudo apt install /полный/путь/к/пакету.deb`. Настройки и профили находятся вне установленной программы и сохраняются при её замене/удалении. Временные файлы загрузки остаются доступны установщику и могут очищаться средствами ОС.

Android использует официальный RuStore In-app Updates SDK: проверка, выбранное пользователем скачивание, затем отдельная установка. Нет RuStore / входа / разрешения / опубликованного приложения — явное сообщение и кнопка официальной страницы магазина. Прямого скачивания APK с GitHub нет. [RuStore SDK](https://www.rustore.ru/help/sdk/updates/flutter/10-5-3).

## Сборка

Общая версия — `version: major.minor.patch+build` в pubspec.yaml. Для публичного Windows MSI увеличивайте также major/minor/patch: Windows Installer не сравнивает четвёртое поле версии. Build должен увеличиваться для каждой публикации, особенно Android versionCode. PackageInfo читает фактическую версию установленной сборки. Не меняйте package id или Android ключ при обновлении.

- Windows: Flutter SDK проекта + VS 2022 C++ + WiX Toolset 4.0.6 (версия CI; уже настроенный WiX 7 также проверен). `tools/package-windows.ps1` собирает полный bundle, sidecar, Isar и app-local VC143 CRT. Можно передать `-Compiler <wix.exe>`. Результат в output/dist. `tools/test-installer.ps1` проверяет изолированный install/reinstall/uninstall; отказывается работать, если уже существует пользовательская установка ServerDeck.
- macOS: на Mac нужной архитектуры `bash tools/package-macos.sh`. Flutter/Xcode/CocoaPods и Dart нужны только на машине сборки. Скрипт копирует sidecar и Isar, делает DMG. `MACOS_SIGN_IDENTITY` задаёт Developer ID, `MACOS_NOTARY_PROFILE` — заранее сохранённый профиль notarytool; без них получается локальная ad-hoc сборка, а не проверенный публичный релиз.
- Ubuntu: `clang cmake ninja-build pkg-config libgtk-3-dev libstdc++-12-dev dpkg-dev file`, Flutter SDK; `bash tools/package-linux.sh`. Зависимости DEB вычисляются по ELF через dpkg-shlibdeps. ARM Linux не заявлен: поставляемая Isar library x86_64.
- Android: JDK 21, Android SDK/NDK, Flutter. Создайте **не коммитящийся** android/key.properties: `storeFile=/полный/путь/к/ключу.jks`, `storePassword=...`, `keyAlias=...`, `keyPassword=...`. `tools/package-android.ps1` требует production key. На Linux можно вызвать `flutter build apk --release` при тех же key.properties. `-LocalTest` собирает APK с debug-подписью и именем LOCAL-TEST; его нельзя публиковать как production. Без ключа обычная CI-сборка выпускает unsigned review APK.

## Публикация

`.github/workflows/desktop-release.yml` проверяет PR и запускается вручную или по тегу `v<полная-версия+build>`, строит Windows, оба Mac, Ubuntu, Android и сохраняет артефакты. Для desktop тег или выбранный create_draft создаёт **черновик**, не опубликованный релиз. Используется точная ревизия Flutter из проекта. Для другой ревизии сначала проверьте совместимость и lock-файлы.

Перед публичной desktop-поставкой подпишите Windows MSI Authenticode, Mac приложение/вложенные бинарники Developer ID, выполните notarization/staple и проверку Gatekeeper, затем заново выполните `python tools/release_manifest.py --assets output/dist --output output/dist/serverdeck-update.json --require-all`. Хеши должны соответствовать окончательно подписанным файлам. Замените assets в черновике этими файлами и проверьте native установку в чистом аккаунте. Только после этого издатель публикует черновик. HTTPS и хеш манифеста защищают передачу, но не заменяют подпись издателя.

RuStore: зарегистрируйте `dev.unng.serverdeck`, сохраните постоянный ключ подписи, подготовьте карточку/скриншоты/описание и требования магазина, загрузите подписанный APK. Для SDK создайте проект package/signature в консоли и пройдите модерацию. Проверьте обновление с меньшего versionCode на устройстве с актуальным RuStore, авторизацией и разрешением установки. Первая публикация и модерация требуют учётной записи издателя и не выполняются локальным билдом. [Требования публикации](https://www.rustore.ru/help/developers/publishing-and-verifying-apps/app-publication), [подписи](https://www.rustore.ru/help/developers/publishing-and-verifying-apps/app-publication/apk-signature).

## Границы текущего приложения

Desktop locald остаётся отдельным процессом; Android запускает его внутри процесса приложения с приватной Isar и loopback API. Рабочая область на телефоне прокручивается горизонтально, навигация и кнопка обновлений доступны. Полный мобильный редизайн не входит в поставку пакетов.

Существующее хранилище SSH-секретов использует Windows Credential Manager. macOS Keychain, Linux Secret Service и Android Keystore для SSH ещё не реализованы; пакеты не означают проверенную поддержку SSH-доступа на этих ОС. Реальные server install/service actions остаются за прежними gates.

Выполненные проверки и ограничения: [Spec Kit verification](../specs/003-desktop-distribution/verification.md).
