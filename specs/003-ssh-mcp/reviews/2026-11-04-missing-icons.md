# Missing workspace icons — 2026-11-04

Scope: 001/R016, 002/T046, 003/T082. Исправление glyph delivery и иконок
вкладок/общих настроек; остальные отличия от HTML макета не входят в этот fix.

## Наблюдение и решение

Font в запущенном прежнем EXE и build tree совпадал по SHA256
`b7b605084cfa8ac4e97c51c7e2dd7d0208aecbf91cf7f73331350a0d4eb429c7`,
размер3876 bytes. Unicode cmap не содержал memory_outlined, developer_board_outlined,
storage_outlined, power_outlined, check_circle_outline, add. Полный SDK font
1645184 bytes содержит эти glyphs. Конкретная причина устаревания subset в cache
не установлена. Новый release не использует icon subsetting и перед упаковкой
проверяет точное совпадение bundled font с полным font закреплённого SDK.
Проверка старого артефакта отклоняет неполный font (ожидаемый отказ).

C16 получает обязательные icons, видимые labels и tooltips. Все callers обновлены
напрямую; profile workspace передаёт apps/description/task_alt/tune. Общие настройки
получают settings_outlined. Семантика и действия прежние, новых backend функций нет.

## Порядок и проверки

Независимое package review `/root/review_missing_icons_spec`: замечаний не найдено,
готовность установлена для этого scope. Сначала реализован продукт/tooling,
потом добавлены и запущены units.

- tools/test-unit.ps1: exit0; format256/0changed, analyze0issues, boundary77files,
  Flutter657, offline schema2 и release-font5 Python units прошли.
- flutter test test_design/components: exit0,120passed,1opt-in capture skipped.
  Новый synthetic C16 тест; feature layout acceptance не добавлялся.
- lychee specs/**/*.md:195total,189OK,6excluded,0errors до этого журнала;
  финальная проверка ссылок выполняется после добавления журнала.
- tools/build-release.ps1 -OutputDirectory output/release-icons: exit0, Windows
  release, full-font equality audit и существующий packaging/import audit прошли.
  EXE SHA256 `c3fb205211c35e5253cfa10c5dbcbc7f0d51222f90e71d7ffc3e4c2bf60216df`.
- git diff --check: exit0.

Логи: output/missing-icons-{unit,components,links,build,old-font-audit}.log
(локальные ignored artifacts). Runtime GUI/SSH/real DB/VM не использовались как тест.
Запуск новой сборки не подтверждён этим разделом: прежний EXE ещё работает.

## Итог независимого review/fix loop

review_missing_icons_code: одно P3 — canonical пример C16 не передавал icons.
Исправлен пример и добавлена001/R017 без удаления завершённой истории.
После docs-only fix lychee повторно exit0:195total189OK6excluded0errors;
git diff --check exit0. Код/tests/build не менялись после успешных проверок выше.
Fresh review_missing_icons_final: замечаний не найдено, готовность подтверждена
для ограниченного icon fix. R016/R017/T046/T082 закрыты после clean review.
Payload manifest содержит full font1645184bytes, SHA256
`d9865b671a09d683d13a863089d8825e0f61a37696ce5d7d448bc8023aa62453`.
