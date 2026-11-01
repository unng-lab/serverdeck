# Исследование прямого SSH — 2026-11-01

Плановая фаза0 существующего001; read-only research, без runtime-проверок.
Два отдельных research tasks изучили текущий код, данные и штатные средства ОС.

## Решения

- **Выполнение**: engine компилирует один поддержанный эффект в одноразовый shell
  script и запускает отдельную transient service. Никакого remote supervisor,
  Python/Ansible, постоянно установленного helper или нового сетевого API.
  Альтернатива ephemeral upload прежнего executor отклонена: сохраняла бы
  заменяемый компонент, его зависимости и privilege boundary.
- **Независимость от SSH**: stage root-owned input и null stdin service вместо
  detached чтения из SSH stdin. `systemd-run --pipe` привязывает descriptors и
  ожидание, а Type=exec подтверждает exec, не результат операции.
  Основание: [systemd-run255](https://www.freedesktop.org/software/systemd/man/255/systemd-run.html).
- **Конкуренция**: постоянный inode flock сериализует transitions; durable owner
  и не удаляемые plan markers сохраняют exclusion после смерти процесса/reboot.
  Один flock без durable tombstone непригоден: ОС освобождает lock при закрытии fd.
  Основание: [flock](https://man7.org/linux/man-pages/man1/flock.1.html).
- **Поздний launch**: worker сам проверяет owner/token/stop до committed start.
  Stop и start линеаризуются под общим lock; reconcile не запускает unit повторно.
  Cgroup stop не доказывает остановку намеренно запущенного сервиса БД.
  Основание: [systemd.kill255](https://www.freedesktop.org/software/systemd/man/255/systemd.kill.html).
- **Identity**: application-specific HMAC machine-id остаётся приватным correlation
  key, а удалённый общий owner — фактическим механизмом сериализации aliases.
  Основание: [machine-id255](https://www.freedesktop.org/software/systemd/man/255/machine-id.html).
- **APT**: exact versions/pins, signed metadata, отсутствие automatic update и
  изменения соседних пакетов; штатные locks не подменяются ServerDeck flock.
  Основание: [apt-get Ubuntu Noble](https://manpages.ubuntu.com/manpages/noble/man8/apt-get.8.html).
- **Данные**: существующие schema3 collections остаются. Capsule format2 отделяет
  direct планы от historical format1 без переписывания IDs/digests/history.
  Отдельного new store/sidecar для automation нет. Неопределённые прежние jobs
  требуют conservative workspace-wide write block: старый executor UUID
  не доказывает соответствие новой SSH machine identity.
- **Scope**: текущие unit/static результаты не доказывают настоящий SSH/systemd,
  атомарность FS, установку БД или готовность Windows-поставки.

## Закрытие первого независимого spec review

Два confirmed gaps устранены дополнительными решениями: local durable dispatch
линеаризует authority, bounded one-step permit привязан к boot uptime<=5s и
не продлевается при SSH loss; resource provenance — protected data из verified
direct install/config result, не fixed registry сам по себе. Атомарная видимость
resource records определяется final step result, existing/historical installations
не получают automatic adoption. Дополнительно определён exact local Job.sshDispatch
record для durable permit без новой Isar collection. T422–T424 и AC-SSH-03/12
фиксируют реализацию и проверки. Нужен свежий completed review; этот текст
не заменяет его результата и не объявляет пакет готовым самостоятельно.

## Закрытие второго review и package autostart

Direct capsule2 объединяет DB file write/syntax/restart/5postchecks в один
declared compound effect. Historical capsule1 сохраняет отдельный restart;
его отложенные checks не переносятся в новый исполнительный путь. Это закрывает
разрыв provenance/permission между file и activation без скрытого restart
в reconcile. T425 и AC-SSH-12 задают нормальный и отказные варианты обеих БД.

Дополнительно зафиксирован transient policy-rc.d101 guard: native pre-install
hook создаёт только отсутствующий guard, post-invoke убирает только собственный
exact guard, существующая чужая policy блокирует recipe. Это сохраняет отсутствие
package autostart до initial loopback/auth/settings. Основание: APT2.8.0
[hook ordering](https://github.com/Debian/apt/blob/2.8.0/apt-pkg/deb/dpkgpm.cc)
и [frontend/inner lock distinction](https://github.com/Debian/apt/blob/2.8.0/apt-pkg/deb/debsystem.cc).
Вывод о нахождении hooks внутри общей frontend lock — анализ исходников,
не runtime proof. Crash residue остаётся unknown/occupied и не очищается
read-only reconcile. Реализация/отказные проверки —T426.

## Закрытие третьего review: stopped lifecycle

Для verified inactive БД определены offline ownership/package/unit/parent/file/
process proofs без недоступного SQL. Start/restart снова требуют live health/
settings после активации; failed/unknown не маскируются inactive. Compound config
из inactive блокируется с предложением отдельного согласованного start.
AC-SSH-13/T427 охватывают обе БД и app restart между jobs. Пример повторного
stop/start одного ресурса в одном AST не принимается как новое требование:
прежняя grammar запрещает repeated resource; supported lifecycle — разные plans.

## Retained dispatch authority — 2026-11-01

Read-only research `dispatch_binding_research` установил, что grant.replace
заменяет единственный grant row, а receipts сохраняют ID/revision/time без старого
expiry. Job.createdAt и поздний updatedAt не определяют время выдачи отдельного
шага. Поэтому прежний authority digest после replacement нельзя независимо
восстановить из старого payload. Existing knownGrantEpoch специально различает
известную текущую issuance и неизвестную историческую; текущая policy не должна
переопределять старую отправку.

Решение: только новый sshDispatch сохраняет3минимальных поля authorizedAt,
grantRevision/grantExpiresAt (null для owner-origin), immutable вместе с permit.
Остальной canonical authority input восстанавливается из retained job/plan/
approval/delegation. Graph проверяет конкретную revision/issuance и binding;
writer отдельно доказывает current authority. Новых credentials, collection,
переиздания старых jobs или runtime compatibility fallback нет. T434 фиксирует
решение/проверки; готовность уточнения требует отдельного spec review.

Обязательные технические решения отражены в [контракте](contracts/direct-ssh.md).
Продуктовых TBD, отложенного выбора architecture и нового runtime prerequisite нет.
