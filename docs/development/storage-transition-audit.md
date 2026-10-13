# Аудит замены хранения: T062

## Проверяемый вопрос

Исторический review15 обнаружил несовместимость общего JSON quota16MiB с native Isar representation одной encrypted aggregate записи. Пользователь затем уточнил: средствами ОС защищаются ключи, пароли и passphrase; обычные metadata не шифруются приложением. T063 заменяет прежнюю архитектуру. Этот аудит проверяет устранение исходного ограничения заменой, а не уменьшение старого quota.

## Текущая реализация

- `envelope_crypto.dart`, `state_envelope.dart`, `state_envelope.g.dart` отсутствуют в production storage directory; поиск production `lib/` и locald `lib/` не обнаружил AES/HKDF/workspace aggregate path.
- [Records](../../packages/serverdeck_locald/lib/storage/records.dart) задаёт пять generated collections и сериализует отдельные документы. UTF8 bounds: workspace/settings/receipt4KiB, profile16KiB, credential512KiB. Единой persisted записи всего WorkspaceState и quota16MiB нет.
- [Repository](../../packages/serverdeck_locald/lib/storage/state_store.dart) открывает native map64MiB и сохраняет изменённые rows, deletes, receipt и store revision одной durable transaction. [Schema preflight](../../packages/serverdeck_locald/lib/storage/native_schema.dart) проверяет пять native schemas до изменяющего open.
- [Custody](../../packages/serverdeck_locald/lib/storage/key_custody.dart) защищает access secrets через UserProtection/CurrentUser DPAPI. Отдельный DPAPI receipt-key используется для HMAC digests; он не шифрует metadata и не заменяет aggregate encryption key.
- [Data model](../../specs/001-service-foundation/data-model.md) и [runtime contract](../../specs/001-service-foundation/contracts/runtime-storage.md) согласованы с этой структурой. RAM WorkspaceState объединяет rows для обработки и проверки, но не сохраняется единым encrypted JSON.

## Фактическое evidence

T063/T017/T019/T020/T021 отмечены выполненными с историей checks и independent reviews в [Tasks](../../specs/001-service-foundation/tasks.md) и [verification](foundation-verification.md). Дополнительно проверены текущие, отдельно ограниченные результаты:

- T193 aggregate: `.local/available-acceptance-5de3b014705e44bc9a1910feecfbbdc9/result.json` — passed11phases, fullAcceptance=false. Positive SecretMarkers читает обычные persisted metadata до DPAPI unwrap, затем проверяет фактический roundtrip access secrets; unsafe ACL acceptance не заявлена.
- T197: `.local/audits/t197-core.txt` — rebuilt CoreStorage8cases accepted, включая repository, credential lifecycle, mutations, API и channel. Native fixture `6fe8f21caea245ffb5f74f4e15393745` сохраняет accepted.json и отдельные case proofs.
- Production source/file checks этого аудита выполнены read-only; новых native tests, builds или crypto operations для T062 не запускалось. Предыдущие результаты не названы новым запуском.

## Критерий закрытия

Исходный дефект устранён отсутствием требуемой одной aggregate записи и её quota16MiB в действующей архитектуре. T062 закрыт как superseded/replaced после завершённого независимого storage_transition_obsolete_limit_review без замечаний. История review15 и completed tasks сохраняется; старое изменение лимита не выполняется.

Это не приёмка всего хранения или 001.1: T039–T041/T045/T048, fullQ/All/CI, reboot/other-user и конкретная отклонённая unsafe-ACL проверка остаются открытыми. Аудит не подтверждает private data безопасность всех возможных каналов или полный native dependency/license provenance. Exact system-denied действия не повторялись и не обходились.
