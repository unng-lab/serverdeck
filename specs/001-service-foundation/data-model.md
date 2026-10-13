# Data model v1 — 001.1

Только locald владеет моделью. [Plan](plan.md), [API](contracts/local-api.md), [custody](contracts/runtime-storage.md).

## Общие типы и validation

- IDs: lowercase UUIDv4/CSPRNG, не основаны на name/address. ProfileId создаёт UI до create и сохраняет при retry. WorkspaceId случайный; default path не идентичность.
- Revisions: decimal strings uint63. Profile/Settings entity revision начинается1, storeRevision0 для empty. CredentialRecord.revision — исключение: это снимок Profile.credentialRevision, не собственный счётчик новой entity. Его правило задано ниже. Нет wraparound: overflow отклоняет запись. UTC RFC3339 milliseconds задаёт locald.
- Text обычных полей: UTF8/NFC; trim name/address/user/tags. Секретные строки password/privateKey/passphrase сохраняют исходную последовательность Unicode и UTF8 bytes, без trim/NFC/преобразования переводов строк: иначе SSH-доступ может измениться. Запрещены NUL/C0/C1 controls кроме LF/CR в key PEM; malformed Unicode/UTF8 отклоняется. Length обычных строк — Unicode scalars; secret bounds — UTF8 bytes. Repeated JSON keys и unknown fields отклоняются.
- Name1–128; address1–253 — IPv4/IPv6 без brackets либо ASCII DNS A-label, без scheme/slash/inline port/whitespace. IDN преобразуется UI в A-label до API. Port1–65535 default22; user1–64 без whitespace/control; tags≤16, каждый1–64, уникальны после NFC. Duplicate target разрешён: разные profiles не доказывают разные physical hosts.
- ProfileJSON≤16KiB; password непустой≤4KiB UTF8; privateKey≤64KiB PEM/OpenSSH envelope; passphrase≤4KiB. Здесь проверяются type/size/envelope; crypto key parsing и SSH usability относятся к001.2, не обещаются по факту save.
- Canonical JSON для digest/manifest/DPAPI wrappers: NFC ordinary validated strings и object keys; значения полей password/privateKey/passphrase сохраняются verbatim. Object keys sorted Unicode codepoint order; compact JSON без whitespace; string escaping стандартный JSON без ASCII-only преобразования; integer fields десятичные без leading zero, revisions остаются strings, arrays сохраняют порядок. Не использовать runtime map iteration order. Golden vectors проверяют bytes на обеих сторонах; canonically equivalent, но byte-different секреты имеют разные digests.

## WorkspaceState — согласованная модель отдельных обычных записей

| Поле | Тип/default | Проверка |
| --- | --- | --- |
| schemaVersion | integer1 | Unknown → incompatible |
| workspaceId/receiptKeyId/ownerSid | UUID/UUID/string | Совпадают с manifest и DPAPI wrapper технического HMAC key |
| storeRevision | decimal `0` | +1 только на committed mutation, не replay/read |
| profiles | map UUID→Profile, empty | ≤250, map key=id, unique |
| credentials | map UUID→CredentialRecord, empty | Один profile owner, no dangling references |
| settings | Settings | Initial revision1/defaults |
| receipts | map requestId→MutationReceipt, empty | ≤10 000, immutable, no expiry/auto eviction |

Нет сериализации всего пространства в одну запись и aggregate quota16MiB. RAM WorkspaceState объединяет данные отдельных записей, но не является persisted JSON aggregate. Обычные поля, ссылки, ревизии и receipts не шифруются приложением. Секреты доступа присутствуют только в DPAPI protectedBlob. Exact native schema и per-record bounds заданы в runtime contract; RESOURCE_LIMIT не меняет state.

Serialization v1: каждая запись имеет ровно перечисленные поля, без extension maps; `MutationReceipt.inputDigest` — canonical standard base64 с padding для 32-byte HMAC. Одна receipt на committed mutation, storeRevision+1, no eviction: storeRevision равна числу receipts; committed store revisions положительны, уникальны и покрывают 1..storeRevision. Entity revision профиля≤storeRevision; Settings.revision≤storeRevision+1; access revisions≤Profile.revision; connectionRevision=trustRevision в001.1. CredentialRecord immutable, createdAt=updatedAt. Startup проверяет эти согласованности, refs, schema, cardinality и DPAPI availability всех blobs. Полностью пустой staging содержит исходные defaults settings, нулевой storeRevision и отсутствие профилей, credentials и receipts.

## Profile

Persisted receipt result проверяется по ревизии своего commit, а не по текущей entity: profiles.create.entityRevision всегда1; profile result.entityRevision≤result.storeRevision; settings result.entityRevision≤result.storeRevision+1. Update повышает исходную entity revision, поэтому profiles.update/settings.update result.entityRevision≥2. Delete возвращает последнюю revision до нового commit, поэтому profiles.delete result.entityRevision<result.storeRevision. Entity могла позднее измениться или быть удалена, поэтому historical receipt не обязан совпадать с current entity revision.

`id,revision,name,address,port,sshUser,tags,credentialRef:null|UUID,credentialRevision,connectionRevision,trustRevision,createdAt,updatedAt`. При создании Profile все его revisions1 независимо от того, задан ли первоначальный credential. CredentialRef null допустим. При последующем update Profile revision +1; connectionRevision +1 при изменении address/port/user; credentialRevision +1 при replace/remove (включая remove уже пустого доступа); trustRevision +1 при connection change. Keep не меняет credentialRevision. Name/tags не меняют access/trust revision. Delete атомарно удаляет credential blob/link.

Trust/cache/jobs в001.1 ещё отсутствуют: delete/update не ждут будущий coordinator. При001.2/001.3 новые сущности должны расширить transaction guards, invalidation и unknown protection, а не оставить «jobs всегда отсутствуют». Wire capabilities честно false. Local selection не SSH trust.

## CredentialRecord

`id,revision,profileId,kind:password|privateKey,protectedBlob:base64,createdAt,updatedAt`. Каждый replace создаёт новый случайный credentialId, удаляет прежнюю запись и атомарно меняет link. Revision новой записи **равна получившейся Profile.credentialRevision**, может начинаться с2 или выше; отдельного revision-счётчика у CredentialRecord нет. При первоначальном create с credential обе ревизии1. Create без credential → credentialRevision1/ref null; последующие replace → revision2/refA, remove → revision3/ref null, replace → revision4/refB (B не A). Keep сохраняет запись/ревизию. Startup проверяет equality для каждого существующего link; отсутствие blob при ref null нормально.

DPAPI CurrentUser wrapper содержит version1/workspace/profile/credential IDs/kind/password либо key/passphrase. Entropy включает product/workspace/profile/credential/version. Защищённый blob хранится напрямую в обычной CredentialRecord, без дополнительного AEAD слоя; read API его не возвращает. DPAPI wrap до transaction: failure не меняет Profile. Startup проверяет refs и DPAPI availability всех blobs до ready; transient plaintext не сохраняется в state/log. UI input очищается после save/cancel; гарантированное удаление GC copies/swap не обещается. CreatedAt/updatedAt immutable CredentialRecord равны времени её commit; timestamps удалённой записи не переносятся.

## Settings

`revision:1,theme:system|light|dark` default system, `reduceMotion:boolean` false, `selectedProfileId:null|UUID` null. CAS settings.revision, atomic receipt/storeRevision. Delete selectedProfile сбрасывает reference и повышает settings revision в той же transaction. Первый UI ru-RU с system locale formatting, отдельного language preference нет. Bootstrap identity/readiness не user settings.

## MutationReceipt

`requestId,inputDigest,operation,profileId:null|UUID,result:{entityId:null|UUID,entityRevision:null|decimal,storeRevision:decimal,deleted:boolean},committedAt`. Digest HMACSHA256 отдельным случайным receipt key32bytes под DPAPI по canonical validated operation+params+expectedRevision, не token/session/requestId. HKDF и ключ шифрования базы не используются. Receipt не содержит raw requests/secrets, result compact, UI перечитывает entity. Receipt после delete сохраняется.

Persist только successful committed mutations. Validation/CAS/quota failures не создают receipt/state change. Same id/digest возвращает original result, даже если entity позднее изменена/удалена; UI перечитывает, не применяет его как current model. Different digest даёт IDEMPOTENCY_CONFLICT. Inflight регистрация/status read сериализованы до async/native работы; duplicate присоединяется к одной операции. Отменённая до старта queued операция без живых requesters удаляет только ephemeral inflight, не имеет receipt/эффекта и возвращает not-found; тот же id/input можно отправить снова при живом owner. Running/неопределённый commit не трактуется not-found. Полная семантика в Local API. Auth failure не раскрывает receipt existence.

## Atomic transaction/crash

Время новых commits — UTC RFC3339 milliseconds с persisted lower bound: locald выбирает максимум текущего UTC wall clock, всех сохранённых Receipt.committedAt и Profile.updatedAt. Одинаковые timestamps допустимы; порядок mutations определяется storeRevision, recent — descending storeRevision. После reopen floor снова получается из проверенного persisted state, не из RAM предыдущего процесса. Коррекция часов назад не делает updatedAt меньше createdAt/прежнего updatedAt и не нарушает timestamp ordering recent. Это logical commit timestamp, не точный physical clock/elapsed deadline; таймеры/сроки от него не вычисляются.

Serial coordinator: validate → receipt/inflight lookup → CAS/guards → clone RAM model → DPAPI wrap/remove → update refs/revisions/result/receipt → serialize affected records/check per-record bounds → durable Isar writeTxn всех изменённых/удалённых записей и storeRevision → смена RAM model → reply. Native wait не внутри transaction. Before-commit error оставляет old state. RESOURCE_LIMIT при доказанном rollback оставляет ready; неопределённый commit/storage error переводит в storage-blocked до reopen/validation, без false success. Process death до commit сохраняет old state, после — new state+receipt вместе. Нет открытых секретов в journal/UI cache/temp или orphan credential persistence.

## Compatibility

API major1/storage schema1/credential wrapper1/receipt-key wrapper1. Старый ServerDeck не читается. Прежний экспериментальный StateEnvelope не принимается и не мигрируется автоматически. Неизвестный формат даёт incompatible с сохранением bytes; no downgrade/rewrite/new empty database. Следующие этапы обязаны создать migration/additive API design до Tasks. Согласованная подмена/откат обычных данных не покрывается.

## Native build artifact — T232/T233

[Native artifact contract](contracts/native-artifact.md) defines build-only recipe, immutable candidate, dependency graph, source archive, qualification receipt and active pointer. These are tooling entities outside the user's Isar database: no row, credential envelope, workspace schema or Local API version change. State progression is prepared → built/unqualified → qualified → active; failure preserves the previous active artifact. Hash/source/test-snapshot mismatch invalidates qualification and blocks copying. The receipt records passed phases and exclusions separately; fullAcceptance=false does not become full product readiness.
