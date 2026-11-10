# Проверка реализации

Это руководство unit-приёмки. Оно не запускает продукт, реальную Isar или SSH.

1. Fake console: через реальные маршруты console.* отправить тестовый ввод,
   получить общий UI/MCP вывод, проверить busy/revoke/EOF и отсутствие автоповтора.
   Подтверждение ввода не утверждает завершение команды.
2. Fake repository/owner: software.save→get→list; все пять полей совпадают.
   Изменить редакцию; stale update/delete возвращают CONFLICT без затирания.
3. Внедрить failAfterWrite/failCommit: карточка, событие, receipt и dataRevision
   и inventory snapshot profilesListRevision откатываются вместе.
   Совпадающий retry в24h не дублирует запись/событие.
   Повтор committed save/delete/note после удаления профиля возвращает прежний
   MutationValue без восстановления строк; отозванный доступ блокирует такой replay.
4. Записать note ИИ, удалить карточку, прочитать её журнал по softwareId;
   проверить автора/время/снимок имени, отсутствие raw terminal payload.
5. Сменить endpoint профиля: original target виден; update/note старой карточки
   конфликтует, delete остаётся локальным. Profile cascade не трогает чужие данные.
6. Проверить list budgets/cursors, включая многостраничный MCP обход с auth-clock
   между запросами без ложных конфликтов; пределы записей и eviction журнала;
   revoke перед replay/transaction/response блокирует доступ.
7. Functional widgets на fake owners: список, форма, конфликт, ошибка записи,
   локальное удаление, история, пометка другой цели, явное копирование задания анализа.
8. Discovery journey на fake console: ИИ-клиент читает синтетический вывод,
   предлагает карточку и сохраняет обычным software.save. Нет фонового обхода хостов.

После кода выполнить root dart format --output=none --set-exit-if-changed .,
flutter analyze, flutter test и tools/check-test-boundaries.ps1.
Проверить обе JSON registry, schema/число27/неизменность21 исходных tools.
После документов: lychee "specs/**/*.md". Затем независимый review/fix loop.
Design/layout и real integration/e2e gates не вводятся.

## Таблица ПО — обновление T038

На fake owners проверять C06 rows/колонки название/версия/служба/хост,
unknown и полные значения, выбор одной записи/замену/закрытие, refresh/reset/prune.
Действия прежних CRUD/conflict/history/console tests сначала выбирают строку.
Проверять данные/семантику/enabled/callbacks, не геометрию или адаптивные матрицы.

## Компактные события — T034–T036

На fake owners/repository проверить нормальные CRUD events и заметки UI/MCP,
host-level note и softwareName snapshot после удаления карточки. До раскрытия
доступна только сводка по UI-контракту; после — полный literal summary/метаданные.
Включить Unicode на границах160 (целиком) и161 (159+«…», итог160), CR/LF/TAB, длинный текст, whitespace-only,
отсутствующие optional поля и UTC fallback. Проверять data/selectable/callbacks,
не размеры или число реально отрисованных строк feature screen.
Строки C07 и действие C02 доступны через pointer/Enter/Space; независимость
событий и выбора записи ПО, отсутствие
owner/domain/SSH эффектов; refresh сохраняет оставшиеся id, новые/вернувшиеся
после удаления из выдачи закрыты. Профиль/историческая страница/фильтр истории
сбрасывают; фильтр списка ПО не сбрасывает события. История по-прежнему paging25,
latest-first и сохраняется после удаления карточки в рамках retention.
Команды и fresh review — обязательный gate выше; только unit/static scope.
