# Проверка перехода на прямой SSH

Это static/unit процедура для [плана](plan.md), не инструкция менять реальный сервер.

1. Через `tools/foundation-sdk.ps1` выбрать pinned Flutter3.47.7/Dart3.13.5.
2. Выполнить `tools/test-unit.ps1`: repository format, root Flutter analysis/test,
   все текущие package analysis/unit suites и RAM bundle checks.
3. Выполнить `lychee "specs/**/*.md"`; устранить broken links.
4. Сопоставить FR-SSH-001–015, AC-SSH-01–11 и SC-SSH-01–04 с [задачами](tasks.md)
   и реальными unit assertions. Выполнить Analyze до Implement и Converge после него.
5. Запустить независимое read-only review по AGENTS.md с self-contained scope,
   фактическими проверками и исходными artifacts. Подтверждённые findings исправить,
   повторить full checks и запустить свежего reviewer-а до clean completed report.

Unit cases включают root/sudo/prerequisite denial, malformed/oversized output,
current trust/grant revocation, immutable preflight/pins/SQL checks обеих БД,
duplicate plan/attempt/step, two aliases/workspaces, lost launch ACK, поздний worker
после stop, restart/reboot evidence, absent/corrupt receipt, quotas и format1 block.
SSH command strings проверяются как typed compiler output; выполнение shell,
продуктовых процессов, Python, SSH/systemd/APT и real FS/native не запускается.

Ожидается отсутствие старого helper/RPC/Ansible/server packaging в активном пути,
сохранение прежних данных и full passing current suites. В отчёте перечисляются
только фактически выполненные команды; unit simulation не становится runtime proof.
Публикация, commit, реальные profile connections, установка, manual UI и release
не разрешаются этой процедурой.
