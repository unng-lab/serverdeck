# Data Model: presentation003

Модель для [плана](plan.md) и [UI-контракта](contracts/presentation.md). Это ephemeral projections/test metadata, не новые Local API/Isar DTO, wire schemas или persistent entities. Для простых widgets допустимы constructor fields вместо отдельных классов.

| Entity | Поля/источник | Валидация и lifecycle |
| --- | --- | --- |
| VisualReference | Существующие `id/title/group/nav/kind/source/implemented` из [registry](../../docs/design/screens.json) | 98unique IDs,35origin/63concept; `implemented` не acceptance. Demo composition fields не загружаются app runtime |
| AcceptanceBinding | Test/evidence: screenId, A01–A12, ownerFile, ownerFR/AC, taskIds, state, N/A reason, frame/theme/scale, command/result/scope | Каждому35origin есть binding; неисполненный check=`not-run`, не pass. Концептам не приписывается runtime acceptance |
| WorkingContext | Section из shell; profile metadata из ProfileController; target/filter/draft/expanded/scroll у текущего owner | Theme/resize сохраняют State/controller identity. Secret input не копируется в общий context. Pause только если уже предоставляется owner; текущий ServerPanel pause не имеет |
| LayoutProfile | width≤520phone;520<width≤1060compact;>1060desktop | Derived RAM value; bottom Wrap/rail72/sidebar210; padding16/24. Не вызывает service effects |
| DisplayStatus | label/symbol/role/reason/nextStep; optional source/observedAt/receivedAt/target/details из существующего owner | Local readiness, SSH connection, observation quality и operation outcome — отдельные оси. Unknown/missing не заменяются zero/success |
| ActionPresentation | label/semanticName/tooltip/enabled/pending/disabledReason/existingCallback/confirmationContext | Нет callback→нет активной кнопки. Owner проверяет rights/identity/deadline; shared widget не строит request/retry/approval |
| DisplayTargetProjection | Existing authorized ProfileView/name/address/port и matching AutomationProfileRecord из текущих owners; exact serverIds/profileId и immutable plan/inspection identity | Только RAM presentation props, без lookup API/cache. Неизвестный или mismatchedID не заменяется selected profile. При согласии captured targets/metadata связаны с actual identity; изменение/утрата отзывает прежнее согласие поP09 |
| ServerLogRecordContext | Readonly serverId/source/observedAt из captured logs result; matching ProfileView только по ID и connection/credential/trust revisions; missing/malformed identity → unresolved | Factory capture в server_sections.dart; Panel передаёт projection того же result/records, dialog не выводит чужой текущий endpoint. Это ephemeral display value без cache/API/authority; source/две даты/record не подменяются, P10 удаляет весь modal |
| AutomationUiOperation / retained outcome | Максимум1 UI write label/errorCode, отдельная read error/current phase, callback token; только результат своего завершённого owner callback | Начальное состояние пустое; no-op/stale completion не присваивает outcome. Pending retirement/dismiss/owner replacement/dispose очищают RAM context. Нет persistence, нового request identity или authority |
| Profile editor draft/recovery | Route-owned controllers, original captured revision, existing pending projection, explicitly read current same-profile revision/digest и accepted expected head | Metadata limits берутся из protocol validator; callbacks borrowed у existing owner. Pending lock не уничтожает draft; явный retry/dismiss/read/accept сохраняют P06/P09. Late/disposed/replaced contexts не закрывают и не подтверждают новую форму |

## Context transitions

1. Обычная theme/width/textScale смена: меняются styles/chrome; сохраняются разрешённые draft/filter/selection, не создаётся новый controller/read/connect/approval/apply.
2. Navigation сохраняет существующий owner lifecycle. Уход из UI не равен server job cancel или повтору unknown mutation. Blanket keepalive приватных children не вводится.
3. Ready loss/client closed: target/private subtree/secret draft/unconfirmed consent исчезают по действующим epochs/readiness; late reply их не возвращает. Store/job history не удаляются.
4. Новый подтверждённый ready: current snapshots появляются по существующему lifecycle; секрет/approval для автоматического действия не восстанавливаются.

## MetricHistoryProjection

Источник — существующий `ServerController.state.history`, bounded upstream [remote_reads.dart](../../packages/serverdeck_protocol/lib/remote_reads.dart). Максимум120 исходных points в source order, без sorting/interpolation/synthetic timestamps. Parent metrics source/quality/stale/time передаются в presentation constructor, не добавляются в wire DTO.

| Sample field | Series / единицы / отображение |
| --- | --- |
| `receivedAt` | Существующее UTC время точки |
| `cpuPercent` | CPU /% /accent /solid /circle |
| `memoryUsedPercent` | RAM /% /chart2 /dash6-4 /square |
| `rootDiskUsedPercent` | Диск / /% /chart3 /dot2-4 /triangle |

Число — полученный integer0–100; отсутствие/invalid — «нет данных». Каждая series разрывается при missing/invalid value, соседнем time delta>15000ms, равном или обратном времени; path не продлевается до now. Text alternative содержит время/три значения/единицы и явные gaps, наследует quality/source/time контекст и не выдаёт старое наблюдение за текущее. При0samples показана пустота, при1 — одиночное значение/символ без вымышленной линии. Семантика success не выводится из наличия point. Patterns таблицы относятся к актуальным данным; parent stale меняет все curve/legend strokes на dash6-4, сохраняя symbols/names/color roles и явную stale подпись. Геометрия компактного блока и его место относительно actions определены P08 из FR-004-LOCAL-02/03; это presentation layout, не новая модель данных.

## Compatibility

GenericJsonDraftState — bounded route-owned presentation state для общего JSON editor: operation kind(read/durable), собственный active callback/token, связанные validation/result, принадлежность retained request и lifecycle guard. Точный JSON остаётся в прежнем route-owned TextEditingController; helper не создаёт request IDs, не копирует payload в отдельный cache и не изменяет controller. Read success не присваивает исход unrelated pending write; explicit dismiss не уничтожает draft. После close/owner/private epoch retirement поздние completions не меняют UI. Это не новая persistent entity или wire DTO.

Reference/binding существуют только в документации/tests; layout/status/action — в UI RAM. Credentials остаются у текущего `CredentialInputState`, immutable plans/jobs/grants — у существующих controllers/locald. Никакой новый cache/store/API/schema version, migration или retention policy не нужен.
