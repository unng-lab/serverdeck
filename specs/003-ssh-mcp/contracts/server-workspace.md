# Сервер как контекст рабочей области

Этот контракт заменяет прежнее постоянное меню разделов приложения и C12
подробности профиля из FR-337. Он действует совместно с текущими SSH/trust
контрактами; изменение навигации не добавляет удалённых команд.

## Состав и владельцы

- C17 FoundationShell принимает sidebar, child, readiness и owner status/recovery.
  Слева всегда остаётся список серверов; общей навигации ПО/logs/jobs больше нет.
  Старые section-specific slots и FoundationSection удаляются, callers обновляются
  напрямую. C17 не владеет профилями, полномочиями или подключениями.
- ProfileViewPanel владеет поиском, выбранным profileId, разделом и поколением
  navigation session. Слева C04, C07, C02 добавления и отдельная C02 кнопка
  «Настройки приложения»; справа заголовок сервера, компактные C21/C10/C14,
  C13 вкладки ПО/Журналы/Задания/Настройки и содержимое выбранного раздела.
- ProfileController читает getConnection для каждого профиля одновременно с
  существующим чтением trust при refresh. Успех заменяет публичную проекцию;
  ошибка чтения помечает состояние неизвестным, а не успешным. Никаких секретов
  в строках, поиске или tooltip. Canonical backend остаётся владельцем SSH.
- RuntimeView сохраняет status/recovery runtime и открывает общие настройки MCP
  отдельным C12 диалогом из левого меню. Они не зависят от выбранного профиля.

## Выбор и разделы

После запуска сервер не выбран: справа предложение выбрать сервер, список
доступен слева. Выбор только читает и меняет контекст, не начинает SSH. Поиск
фильтрует список, но не сбрасывает выбранный сервер, даже если он скрыт фильтром.
При выборе другого сервера текущая вкладка сохраняется; начальная — ПО.
При удалении выбранного профиля контекст очищается без автоматического выбора
соседа. Переименование сохраняет выбор. Состояние навигации не сохраняется в БД.

ПО, Журналы и Задания — доступные вкладки с явным «Раздел пока недоступен» и
именем выбранного сервера. В этом изменении нет fake-сервисов, журналов, задач,
нового SSH exec или реализации этих будущих возможностей. Настройки сервера
содержат существующие профиль/способ входа/public fingerprints и действия
connect/cancel/disconnect/edit/delete/trust/passphrase. Они доступны и без SSH.
Удаление по-прежнему требует явного подтверждения C12.

## Сохранение и гонки

Form/consent/passphrase остаются C12, но подробности сервера — обычная рабочая
область. Успешный save выбирает именно возвращённый profileId и очищает поисковый
фильтр, чтобы сервер был виден. Новый/connection-affecting save начинает ручную
проверку и автоматически предлагает актуальные first/replace/retain и phrase
только внутри собственной onboarding session. Name-only save не reconnect.

Выбор другого сервера, удаление выбранного, открытие общих настроек, смена
controller и dispose завершают onboarding, убирают его вложенный prompt и
инвалидируют edit/save continuations. Закрытый verification lease дожидается
позднего admission и отменяет только свой exact pending attempt; новая попытка
и established session не затрагиваются. Текущие actor/revision/nonce guards и
лимит 64 показанных tokens сохраняются. При переключении вкладок того же сервера
контекст сохраняется. Поздняя загрузка A не меняет выбранный B.

Мониторинг активен во всех пяти вкладках server workspace; выбор не ограничивает
очередь одним сервером. Общие настройки MCP временно деактивируют collection/
queued admission по правилам004, но сохраняют established SSH. Закрытие диалога
возвращает тот же сервер/вкладку и возобновляет только разрешённую работу.

## Статусы и подсказки

C07 поддерживает compact/error и отдельный status label; error остаётся заметным
при selected. Приоритет строки: changed key → failed NETWORK_ERROR («Связь
потеряна») → другой failed («Ошибка подключения») → needTrust → needPassphrase →
connecting → connected (critical/partial по004) → disconnected/cancelled → unknown.
NETWORK_ERROR включает неудачное установление и потерю SSH; UI не утверждает,
что доказана конкретная причина сети. Manual disconnect не является ошибкой.
Changed key и loss/error имеют короткий текст в строке, остальные состояния могут
быть иконками. Нормальные connection/freshness используют разные символы.

C10 iconOnly и C21 compact+icon показывают tooltip с полным русским названием,
значением/единицей и смыслом состояния при hover и keyboard focus; доступное имя
содержит ту же информацию. CPU — процессор, RAM — память, disk — диск /.
Недоступное значение не равно нулю. 15s freshness и порог90% не меняются.
Сводка и настройки не содержат timestamp/возраст/журнал обновления метрик. Время истории во вкладке «Мониторинг» разрешено контрактом004. Ошибки не сообщаются
только цветом; причины и безопасные next actions доступны в рабочей области.

## Проверка

Только unit и functional widgets с fake owners: выбор/поиск/CRUD, все разделы,
неизвестная проекция, loss/manual disconnect, changed key, partial/critical,
tooltip semantics/focus, stale A/B, late admission, повторные prompts, MCP overlay.
Shared C07/C10/C17/C21 проверяются отдельно в001 на synthetic inputs. Никаких
feature layout/golden/overflow matrices, реальных SSH/Isar/VM/integration.


## Retirement implementation decision (review T078/T079)

Workspace запоминает конкретные Route/NavigatorState при создании prompt; cleanup
не ищет ancestors через disposing BuildContext. При rebind/dispose route удаляется
после frame, generation инвалидируется сразу. Это покрывает одинаковые profileId
у разных controllers и сохранение root Navigator при удалении workspace.

lib/runtime/owned_settings_route.dart: OwnedSettingsRoute удерживает один owner-bound
DialogRoute, NavigatorState и retired latch. RuntimeView создаёт новый session при
runtime/features/settings replacement или admission loss; old session retired до
controller.dispose. Builder захватывает конкретный controller, а не mutable field.
Nested Navigator принадлежит route; MCP confirmation/input dialogs используют
useRootNavigator:false, поэтому удаление outer route уничтожает и вложенные.
Старый finally не возобновляет monitoring нового owner. RuntimeView.dispose
retire route, не оставляя настроек поверх другого host. McpSettingsController
после dispose не dispatch effects. Name-input controller принадлежит своей route
State до unmount; late selected result проверяет mounted/controller identity.


## All profile forms and confirmations (T080)
Одинаковое retirement применяется ко всем C12 профиля: create/edit form, delete
confirmation, trust и phrase. Workspace регистрирует конкретный DialogRoute с
NavigatorState до push и удаляет его из registry при завершении future. Retirement
сразу инвалидирует navigation generation и after-frame удаляет все захваченные
маршруты; builder rebuild уже popped route не меняет registry. Delete continuation
захватывает исходный controller/generation и проверяет их вместе с selected profile
после consent. Старое решение не применяется к новому owner даже при том же id/rev.
Disposed ProfileController отказывает новым обычным create/update/delete/connect
и другим _action; cancelOwnedAttempt остаётся отдельным exact-attempt cleanup,
который может завершить позднюю owned попытку после disposal. Уже допущенная
операция не объявляется откатанной из-за закрытия UI; backend fences сохраняются.


## Trust observation distinction (T081)
Отсутствующий TrustView не означает отсутствие принятого pin. Самостоятельное
canonical connection observation остаётся действительным при отказе getTrust.
Явный needTrust всегда даёт проверку ключа; известный unpinned badge применяется
только к disconnected/cancelled, а не подавляет connected/needPassphrase/connecting/
authenticating. Cached unpinned не отменяет более новое состояние SSH. Changed-key
warning сохраняет свой первый приоритет. Это не fallback старых записей приложения.

## Иконки текущего workspace — 2026-11-04

Вкладки C16: ПО — apps_outlined, Журналы — description_outlined,
Задания — task_alt, Настройки — tune. Текст вкладок остаётся видимым; hover-tooltip
повторяет название. Кнопка «Настройки приложения» получает settings_outlined рядом
с текстом. Иконки метрик, соединения, актуальности, sidebar/add используют текущий
MaterialIcons из002/T046. Данные и действия вкладок не меняются; недоступные разделы
не получают фиктивных данных. Unit checks проверяют callbacks/semantics, дизайн
только на synthetic C16 примерах001; feature screen layout acceptance не вводится.

## Monitoring tab — 2026-11-04

Current C16 order: ПО,Журналы,Задания,Мониторинг,Настройки. Icon monitor_outlined;
visible text/accessibility label «Мониторинг». History content belongs to
[004 hour history](../../004-server-monitoring/spec.md#часовая-история--2026-11-04).
Workspace activation/selection/trust rules stay the same. Current summary and server
settings have no time log; C22 in Monitoring provides historical times and percentages.
