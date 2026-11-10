# ПО → логи службы: evidence

## Scope — 2026-11-10

User: убрать колонку Хост и добавить Логи, ведущие в журнал службы.
Текущие требования:008 FR-815/AC-818 и005 FR-516/AC-516;
[контракт](../contracts/service-logs.md). Выполненные прежние задачи сохранены.

Pre-implementation reviewer /root/review_service_logs_specs: findings0,
готов к реализации. Проверены пакеты005/008, UI/owner/interfaces и обязательные
решения; lychee400/0 и diff-check exit0 переданы reviewer как реальные evidence.

## Реализация

SoftwareView: C06 name/version/service, C10 old-target у имени, исходный адрес
в C18 details; C02 Логи с точным unit и disabled reasons/currentTarget/pending.
ProfileViewPanel: callback → тот же профиль/connectionRevision, section Журналы,
initialService; manual tab/retire workspace очищают transient intent.
JournalView: local search/async source selection, epoch и owner/profile/revision
guards, manual search/source supersedes late selection, явная ошибка.
JournalsOwner: shared add path; ensureService атомарно проверяет expected revision,
возвращает существующий источник до caps или создаёт один новый. Existing pause/
name/payload не меняются. Нет discovery/auto-connect/new remote commands.

## Проверки

- Root `dart format --output=none --set-exit-if-changed .`: exit0,508files0changed.
- `flutter analyze`: exit0,No issues found.
- `flutter test`: exit0,961 passed; `.local/service-logs-full-test.log`.
- `tools/check-test-boundaries.ps1`: exit0,118 Dart files.
- `lychee "specs/**/*.md"`: exit0,400total167unique394OK0errors6excluded2redirects
  до добавления этого evidence; после финальных документов выполняется повторно.
- `git diff --check`: exit0 на текущем scope до финального evidence.

Targeted software/journal suites45 passed и отдельный profile navigation1 passed
до последнего полного прогона. Только fake unit/functional tests: точный callback,
disabled/reasons, поля таблицы/address/old-target, reuse/create/pause/quota,
concurrent duplicate, stale revision при задержке транзакции, rollback,
initial search/source/error, manual cancellation/late profile reply, реальная
связка callback вкладки и сброс intent при manual tabs на подставных owners.

При подготовке тестов исправлены неверное имя метода fixture, ожидания eagerly
построенных строк lazy C06 и лишние non-null assertions. Зависание profile test
устранено созданием fake repository/gate в setUp вне widget FakeAsync и явным
ожиданием owner turns; application code ради теста не подменялся.

Это unit/static evidence. Продукт, SSH/реальная Isar, integration/e2e, layout/
goldens, выпуск и публикация не запускались. Финальное independent review ожидается.

## Итоговое независимое review

/root/review_service_logs_implementation завершил read-only review всего заявленного
scope кода/tests/пакетов005/008 и связанных storage/lifecycle/shared API: findings0,
реализация соответствует новым требованиям, обязательных пробелов нет.
Reviewer самостоятельно прочитал финал961 passed в логе; остальные checks
оценил по переданным реальным результатам. По его разрешению закрыты008 T041
и005 T051, запись добавлена в stages.md. После review application code не менялся.
Link check перед review: exit0,401total167unique395OK0errors6excluded2redirects;
diff-check exit0. Review/fix loop завершён без незакрытых confirmed findings.
Результат ограничен unit/static scope; изменения текущего задания локальные.
