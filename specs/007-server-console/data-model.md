# Data model: Консоль сервера

## Persisted configuration

AppSettings.terminalConfiguration: nullable String. Null — v1 с пустым profiles и defaultId="login". Никакой другой falsy value не означает default. JSON exact keys: {version:1,revision:int>=1,defaultId:string,profiles:[{id,name,path}]}. Unknown keys/version, duplicate IDs, default вне {login,IDs}, >16 profiles, invalid types/bounds — storage error. Максимум serialized UTF-8 32KiB. ID пользовательского профиля canonical UUIDv4, встроенный login отдельно; name1–80 Unicode scalar values after trim; path absolute Linux1–1024 UTF-8 bytes, no NUL/CR/LF. Совпадение имён/путей допустимо, identity — id.

SettingsOwner save(UiActor,expectedRevision,profiles,defaultId) внутри gate/repository transaction. Existing null имеет revision1; успешная запись revision+1, AppSettings.settingsRevision/dataRevision+1 без изменения прочих полей. Ошибка не меняет snapshot/draft. Generated schema readStringOrNull подтверждает default старого record; storage format2 не повышается. ConsoleOwner берёт immutable snapshot при reservation, subsequent CRUD не мутирует session.

## In-memory session

sessionId UUIDv4, ownerEpoch, generation1 (не переиспользуются), server profileId/connectionRevision/SSH sessionId, VersionFence(endpoint/credential/trust/observation/attempt; без profileRevision), shell snapshot {id,name,path?}, state opening|active|ended|disconnected|error, reason?,exitCode?, partial, engine, rawQueue, inputQueue, lease, historyVersion1. До4/server,16 глобально включая завершённые/открывающиеся.

Opening reservation предшествует network. Успех только после PTY+shell ACK; timeout15s/cancel до ready закрывает opening, late events fenced. Ended/disconnected/error сохраняют output read-only, освобождают ввод; close удаляет запись/engine. Trust/endpoint/auth invalidation очищает output до любых новых reads и закрывает канал. Простой disconnect сохраняет буфер. Удаление server profile удаляет его записи. Product IDs не равны vendor protocol channel IDs, retired protocol slots учитываются отдельно.

## Lease

holder: ui либо {clientId,grantVersion,connectionToken}; generation monotonically increasing; token randomUUID, expiresAt monotonicNow+60s. Free — holder/token null. Создатель получает lease; UI first input свободного lease получает его атомарно. acquire свободного lease выдаёт новый token; acquire своим же владельцем возвращает текущий без renewal. accepted nonempty input renews60s; read/replay/acquire не продлевают. UI takeover без ожидания меняет generation/token; old queued actions cancellation сигнализируется синхронно. Empty input invalid. Timer expiry, grant invalidation, MCP EOF, release, close освобождают. Все проверки expiry также выполняются при use, не только timer. Partial remote line не очищается при смене владельца.

## History and parser

Engine single source. screen initially80x24, cols2–512,rows1–200; remote CSI resize ignored. Main scrollback<=10000 physical rows и<=4194304 UTF-8 bytes plain-text rows including LF; active screen отдельно bounded cols*rows; alt scrollback0. Hidden main scrollback учитывается. raw pending<=1048576 bytes; input queued incl encoded wrappers<=65536 bytes. Token/parser caps из [terminal](contracts/terminal.md).

historyVersion увеличивается на каждый принятый output chunk и resize/clear/eviction/alternate switch; truncated sticky true после первого вытеснения, partial также при output limits/неизвестном разрыве. Session snapshot включает cursor cell, activeBuffer, visible rows. Cursor: base64url JSON exact {ownerEpoch,sessionId,generation,historyVersion,section:scrollback|screen,row,scalarOffset}. Encode<=512 chars, decode strict; bad format INVALID_ARGUMENT, stale version => успешный HistoryPage {historyGap:true,rows:[],nextCursor:null} без продолжения; новый read безcursor начинает актуальную историю. Session IDs/epoch fence запрещают доступ к старым данным. Одна страница<=1000 rows/65536 UTF-8 text; MCP envelope<=1MiB. Повторная полная копия screen/scrollback не сохраняется.

## Replay

Owner lifetime ledger keyed clientId+grantVersion, максимум64 principals. При достижении лимита новые mutating principals получают RESOURCE_EXHAUSTED до эффектов; existing ledger не вытесняется до owner shutdown. Разрешение и token bindings живут отдельно.

Each principal highWater=0,nextSequence=1. Новая mutation(operationSequence,ownerEpoch) принимается только sequence=highWater+1 и если нет pending mutation этого principal; reservation увеличивает highWater до effect. sequence>next => CONFLICT; sequence<=highWater ищется среди64 последних результатов: тот же kind/session/canonical payload SHA256 => прежний metadata result, иной => CONFLICT, отсутствующий => CONSOLE_REPLAY_EXPIRED без effects. Записи максимум4096 bytes metadata, no input/history bytes; один pending наprincipal. Итог cached result не восстанавливает lease; если channel binding уже утрачен, клиент должен acquire заново с новой sequence. До lookup и выдачи результата проверяются актуальные grants. После restart epoch отличается, identities отклоняются до effects.

Fingerprints содержат canonical operation+target+expected versions+text/key bytes hash, но не сохраняют plaintext. Input buffer стирается после sending/cancel. Pending запись завершается error/unknown даже при обрыве response. Для закрытия session допускается replay tombstone из ledger после удаления, но только для разрешённого клиента, никогда history. UI не использует MCP ledger.
