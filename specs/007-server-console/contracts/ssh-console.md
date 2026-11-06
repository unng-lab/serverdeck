# SSH console capability

## Ports

ConsoleConnectionPort exposes bind(profileId,expectedConnectionRevision,sshSessionId) returning private ConsoleBinding {fence, generation, open(options,cancellation,onData), listenInvalidation}. Нет raw client или generic exec в public operations. ConnectionOwner реализует capability только для текущего connected/trusted transport. ConsoleSshConnection — optional typed transport interface, StrictSshTransport production реализует его.

## Vendor bounded PTY

SSHClient.startOwnedPty(options) -> SSHOwnedPtyOperation {opened,cancel}. Options: term xterm-256color,initial80x24,path? (null=>shell request),timeout15s,receiveWindow65536,maxPacket32768,synchronous onData, guarded packet sender. Не возвращает SSHSession/stdin/sink. Session exposes sendGuardedData/resizeGuarded/abort/streamsDone/exitCode.

До CHANNEL_OPEN выделяется protocol ID и metadata; максимум16 owned PTY protocol slots на SSH connection, включая pending/retired, независимо от product caps. При cap=>cleanupRequired без disconnect. Cancellation/timeout запрещают новые setup requests; late OPEN_CONFIRMATION synchronously retires+closes channel до любого PTY/shell. Pending-open ID сохраняется до open-failure/peer-CLOSE, не переиспользуется. Request reply FIFO reservation до send; отмена послеreservation retire всего channel. Unsolicited/invalid reply fails only channel. Failure to confirm cleanup retains bounded slot.

PTY ack обязателен до shell/exec; login path null sends shell. Custom path executes exactly one shell-quoted executable path via exec request (`exec '<escaped absolute path>'`), no arguments/concatenated startup commands. Single quote внутри path кодируется POSIX single-quote escape; путь не интерпретируется как команда. Отказ PTY запрещает fallback no-PTY/shell. Ready только после shell/exec ack. Exit status опционален; final output synchronous consumer обработан до streamsDone. No stdin stream buffering.

## Output

Синхронный consumer ставится до первого data event (в том числе pre-ACK); raw queue counts both stdout/extended stderr в wire order,<=1MiB; excess =>partial/outputLimit и abort только channel. Data max32768, processing<=16384; initial receive window65536 и bounded window replenish. Только active binding/generation меняет engine; after trust invalidation drop+clear, afternormal disconnect keep already parsed text read-only. Данные до shell ACK сохраняются в bounded queue и видны как opening output; не считаются input authorization.

## Guarded input and packet boundary

Перед отправкой каждого fragment проверить actor/grant/channel binding, session generation/state/connection fence,lease token/epoch/expiry,cancellation. Internal terminal responses вместо actor lease проверяют active owner/session/trust, но используют тот же queue и byte cap. Queue reservation полного action до enqueue; FIFO actions,<=64KiB всего. Lease revoke/expiry/takeover/EOF синхронно cancels old queued jobs. Remote window ожидание вне gate; update signal/cancellation/deadline без busy-loop. Неподвижный remoteWindow не блокирует owner или other channels; input job terminal timeout15s, partial=>unknown, no automatic retry.

SSHChannelController guarded upload не использует legacy _localStream/_uploadLoop. Единственный uploader берёт<=min(remoteWindow,remoteMaximumPacketSize,32768). Window decrement только при actual packet commit. No remote execution guarantee. Outcome {acceptedBytes,complete|cancelledBeforeSend|outcomeUnknown}; cached metadata без input bytes.

SSHTransport hooks: isKexInProgress, waitForKexReady (terminates on close), trySendPacket(payload) synchronous. false во времяrekey до изменения cipher/SN/nonce и без _rekeyPendingPackets. На true ordinary encode/MAC/encrypt.

_AdmittedSocket hooks: drainWrites,hasPendingWrites,runImmediate(maxEncodedBytes,send). Guarded sender waits drain/rekey outside gate then existing connection admission gate: check connection fence and stopped, check queueempty/kexidle, guard, reserve conservative maxEncodedBytes=payloadLength+256 (<1MiB) and onepacket BEFORE encrypt; runImmediate transfers immutable encrypted bytes to raw.sink.add synchronously with no await. Queue/rekey race=>retry before encryption via readiness futures; cancellation/deadline checked each cycle. No user/debug callbacks inside critical serialization; nested/reentrant immediate prohibited. After write raw.flush runs outside gate and is installed as _tail; reservation remains until flush so generic add queues after it. Never drop ciphertext on revoke. Any unexpected failure after encoding starts fails/closes transport (cryptographic state may have advanced), no plaintext retry. Normal cancelled/denied input before encryption does not close sharedSSH.

## Lifecycle

ConnectionOwner synchronous invalidation notification closes old console admission before another event; captured fence excludes rename. Runtime stopAdmission forbids new actions first, then cancels pending,closeschannels,drains; background UI detach no close. MCP revoke/EOF releases only its input jobs/lease, existing session continues, pending opening by that binding cancelled before ready. Device replies guarded separately. Unit tests use synthetic channel messages/socket sinks/clock, no live SSH,process or integration.

## Unified wait control and fixed opening failures

SSHOwnedPacketSender receives SSHOwnedPacketWait {remaining(),listenCancelled(callback)->remove}. One monotonic deadline spans an input action, all fragments/window/admission/rekey/flush waits; queued time is additionally cancelled by the owner's original15s job timer. Setup uses its opening15s deadline. Strict sender uses removable drain/rekey/cancellation subscriptions and a remaining-time timer, removed on every outcome; it does not attach a fresh timeout continuation to a stalled shared flush/rekey Future for each action. A cancelled gate admission has an inactive latch, so a late callback cannot encrypt/write; its reservation remains until the gate callback physically completes. At most64 active/retired console packet admissions per SSH transport, otherwise RESOURCE_EXHAUSTED before another gate callback. Ciphertext already added to the socket remains in FIFO through flush even if the action returns outcomeUnknown on cancellation/deadline.

Console port opening failures carry a fixed ConsoleOpenFailureCode: ptyDenied,shellDenied,timeout,cleanupRequired,unsupportedServer,networkError,cancelled. Native PTY/shell denial and protocol-slot exhaustion map to these tags without remote messages or payload. UI shows distinct explanations; no fallback shell or retry. Creator actor/request/current grant is checked at every setup packet guard and just before active promotion, independently of asynchronous invalidation notifications.
