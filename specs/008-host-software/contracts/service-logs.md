# ПО → логи systemd-службы

Таблица C06 содержит название, версию, службу; хост — только в C18 подробностях.
C10 «Другой хост профиля» виден у имени ПО. В каждой строке C02 «Логи» рядом
с «Подробности». Это переход к005, а не к metadata-истории карточки008.

## Доступность

Логи доступны только при currentTarget=true, pending=false, непустой service,
проходящей validateJournalTarget(JournalKind.journal, service), и наличии
onLogs/JournalsOwner. Точная строка должна включать `.service`; суффикс/регистр
не угадываются. Disabled причины: другой хост, операция выполняется,
служба не указана, нужен корректный systemd unit с `.service`, журналы недоступны.
Открыть можно offline: это не подключает сервер и не меняет доверие.

## UI и owner

SoftwareView.onLogs(String unit) передаёт исходную строку без shell. ProfileViewPanel
переключает тот же профиль на «Журналы», передаёт initialService в JournalView
для текущих profileId/connectionRevision. Ручной выбор вкладки/смена workspace
сбрасывает intent, чтобы обычное открытие журналов не восстанавливало старый unit.

JournalView ставит поиск unit и через ensureService выбирает journal-источник
строго `(profileId, kind=journal, target=unit)`, без требования discovery cache.
ensureService атомарно проверяет профиль и ожидаемую connectionRevision и затем:

1. Возвращает существующий sourceId, сохраняя name/enabled/payload/checkpoint,
   даже при заполненных quotas. Отключённый источник остаётся на паузе.
2. При отсутствии создаёт обычный источник005 (enabled=true, name — первые80
   Unicode code points unit), соблюдая caps16/profile и1024/store; повторные/
   конкурентные запросы дают один источник. Новые поля и квоты не вводятся.

Новый enabled источник использует штатный read-only scheduler005 при существующем
доверенном подключении; action не вызывает auto-connect, sudo, start/restart,
консоль или discovery. Offline/permission/empty/partial/pause и retry — обычные005.
Сохранение источника не выдаётся за успешное чтение логов.

## Ошибки и lifecycle

Ошибки validation/quota/storage/profile-not-found/revision-changed/shutdown
показываются существующим UI сообщений JournalView; не выбирается иной источник.
Повтор перехода явно повторяет ensureService и безопасно переиспользует запись.
Асинхронный ответ применяется только при прежних owner/profile/revision и
локальном request epoch; новый intent или ручной source/search отменяет старый
отложенный выбор. Уже атомарно сохранённый источник не удаляется при закрытии UI.
Изменение revision до записи отклоняется внутри транзакции. Смена контекста
очищает selection/search/errors; старый ответ не показывает и не перезаписывает их.

Тесты — functional/unit fakes данных, callbacks, авторизации и lifecycle.
Общие C02/C06/C10/C18 и дизайн005/008 не получают feature layout gates.
