# История изменений

## 0.4.0-preview.1 — 2026-11-01

Flutter version: `0.4.0-preview.1+13`. Выпуск исходников с MIT license и сохранёнными
third-party notices; архив и SHA-256 публикуются вместе с точным tag/commit.

- Доменная логика перенесена во встроенный переносимый Dart engine. Desktop UI
  и MCP используют один Host/store, общую авторизацию, sampler и бюджеты.
- Закрытие окна оставляет приложение в полноценном трее; «Выход» завершает app
  и локальный MCP. Suspend/resume сохраняют владение и снимают старые observations.
- MCP запускается тем же executable с `--mcp-stdio --grant-id UUID`, подключается
  только к работающему приложению, без отдельного mcp/locald и автозапуска app.
- Сохранены текущие schema3 IDs/revisions/credentials/trust/grants/jobs и история;
  старые схемы и bridge/API отвергаются без reset/migration/rollback.
- Удалён старый runtime и его test/build inputs. Общий pipeline выбирает ровно
  engine/MCP/protocol/Windows. Неопределённые задания сохраняют occupancy и требуют
  авторизованной сверки; потеря observer не отменяет job и не повторяет submit.
- Определена честная capability matrix шести платформ. Будущие adapters не
  выдаются за поддержку ОС; optional backend/node не реализуется этим выпуском.

- Unit-runner начинает с locked dependency bootstrap перед форматированием;
  проверка работает на свежем checkout без зависимости от старого package cache.

### Проверка и ограничения

Полный текущий static/RAM набор: форматирование, Flutter и четыре package
analyses,766Dart cases (одна static source check,765RAM) и16PowerShell RAM groups.
Итоговые independent aggregate/source reviews не нашли unresolved findings;
35FR/AC/SC и149task chains embedded-поправки приняты в указанном scope.
На release snapshot этот же набор повторно пройден; форматирование385файлов
без изменений, все766Dart cases и16PowerShell groups прошли. GitHub CI status
связывается с точным release commit перед публикацией.

Архив содержит только исходники, а не desktop installer или native-qualified
bundle. Native/Isar/DPAPI/ACL/SSH/Python/systemd, UI/design, реальные isolate/IPC,
hosted packaging/build/install/update/signing/release-binary qualification этим
preview не подтверждаются. Старые tools/API/форматы не поддерживаются; текущие
schema3 данные сохраняются. Готовые бинарники и serverdeck-update.json не включены.
