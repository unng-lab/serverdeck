# Качество требований: переход на прямой SSH

**Дата**: 2026-11-01. **Audience**: независимый reviewer перед реализацией.
Это checklist требований, не список выполненных проверок или source tasks.
Маркеры принадлежат reviewer; генерация оставляет их unchecked.
[Spec](../spec.md) · [Plan](../plan.md) · [Contract](../contracts/direct-ssh.md).

## Scope и согласованность

- [ ] CHK001 Определено ли отсутствие устанавливаемого executor и запрещена ли его маскировка transient upload? [FR-SSH-001, Contract1]
- [ ] CHK002 Согласованы ли роли engine/UI/MCP, recipes006 и права021 без второго пути SSH? [FR-SSH-002, Plan architecture]
- [ ] CHK003 Отличаются ли AST format1, historical capsule1 и direct capsule2 без неоднозначного права исполнения? [FR-SSH-011, Contract4/9]

## Prerequisites и полномочия

- [ ] CHK004 Полностью ли определены platform/tools/root-sudo требования и read-only отказ без скрытой установки? [FR-SSH-003/015, AC-SSH-02]
- [ ] CHK005 Определены ли target/trust/grant/selected-authority проверки до каждого эффекта и последствия отзыва? [FR-SSH-004, AC-SSH-03]
- [ ] CHK006 Исключены ли секреты/raw shell/scripts/paths/SQL из публичных входов, records и diagnostics? [FR-SSH-002/015, Contract2/3]

## Конкуренция и восстановление

- [ ] CHK007 Определены ли host-wide owner/lock/tombstones между aliases/workspace и последствия reboot/unknown? [FR-SSH-005/007, AC-SSH-10]
- [ ] CHK008 Определён ли порядок durable intent → reserve → launch → start → result и duplicate/late worker? [FR-SSH-006, Contract6/7]
- [ ] CHK009 Различены ли cancel/detach/shutdown, частичные эффекты и безопасная граница без kill apt? [FR-SSH-008, AC-SSH-08]
- [ ] CHK010 Заданы ли доказательства read-only reconcile и случаи сохранения unknown/occupancy? [FR-SSH-009, AC-SSH-09]
- [ ] CHK011 Закрыт ли переход old executor host UUID → direct identity так, чтобы новый alias не обходил unresolved job? [FR-SSH-011, Contract9]

## Установка, данные и ресурсы

- [ ] CHK012 Полны ли exact versions/pins/signing/native APT-lock/neighbor/NetBird/data/SQL проверки для обеих программ? [FR-SSH-010, Plan006]
- [ ] CHK013 Заданы ли closed host record formats, custody, quotas, atomic persistence и запрет unsafe cleanup? [FR-SSH-014, Contract6/7]
- [ ] CHK014 Сохранены ли schema3 IDs/secrets/trust/grants/history и запрещён ли автоматический перенос старых согласий? [FR-SSH-011, AC-SSH-11]
- [ ] CHK015 Определены ли UI/API/bundle изменения без enrollment/release/server packaging? [FR-SSH-012/013, Contract9]
- [ ] CHK016 Прослеживается ли каждый FR к решению/контракту/задаче/AC и различены ли unit proofs и runtime qualification? [SC-SSH-04, Tasks402–421]
