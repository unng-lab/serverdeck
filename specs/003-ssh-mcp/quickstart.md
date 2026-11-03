# Unit validation guide — 003 SSH/MCP

## Действующий scope

Только юнит-тесты по прямому указанию пользователя (2026-11-03), AGENTS и
[конституции III](../../.specify/memory/constitution.md). AC/SC — продуктовые
требования, не интеграционные команды. Никаких VM/OpenSSH/stdio subprocess/real Isar
или process-kill gates. Статическая сборка и анализ допускаются.
Результат подготовки пакета не означает выполненную реализацию.

## Предпосылки

[Runtime002 завершён](../002-desktop-runtime/reviews/unit-only-final.md).
Toolchain: [quickstart002](../002-desktop-runtime/quickstart.md).
Git также нужен при сборке для статического reverse-check policy patch;
готовому приложению Git не требуется.
Isar3.4.1, build_runner2.16.2, vendored dartssh2-4.1.0 из проверенного archive/hash,
policy patch по [SSH contract](contracts/ssh.md). Полный schema2; migration logic
проверяется на fake store/native-file boundary и synthetic snapshots.

## Команды после реализации

```powershell
python -m pip install -r tools/unit-requirements.txt
flutter pub get --enforce-lockfile
./tools/generate-models.ps1
./tools/test-unit.ps1
./tools/build-release.ps1
./tools/test-release.ps1
lychee "specs/**/*.md"
```

`test-unit.ps1` включает format/analyze/flutter test/boundary. Native runner
выполняет только unit-labeled adapters/codecs; не добавлять туда product probes.
Общие компоненты001 не меняются; design suite функции не запускается.

## Unit criteria

| Scope | Изолированная проверка |
| --- | --- |
| Profiles/credentials | validation, protected blob boundary, atomic fake rollback, snapshot re-open, no secret projection |
| Trust | A/B/C observations, exact nonce/revisions, first/replace/retain, stale consent, reference counts |
| SSH | memory stream byte policy, parser vectors, no auth before committed consent, chosen method only |
| Connection owner | fake clock30s budget/pause/prompt5min/liveness, cancellation/generation fences |
| MCP router |13definitions vs pinned official schema fixture, invalid inputs/IDs, no delete/exit/admin escape |
| Grants/receipts | fake clock90days/24h/rollback, revoke/rotate/expiry/export errors, authorization before replay/commit/output |
| Native IPC/stdio | fake partial read/write/EOF/identity/DPAPI/ACL outcomes, bounded frames and channels, no owner auto-start |
| UI | data/text/actions/controllers with fake domain owners, ready C IDs only |

Только synthetic credentials/keys. Реальные пароли, host keys и known_hosts не
читаются тестами. Независимое read-only review после doc/code checks обязательно.
Unit/static results не доказывают фактическую связку на чистой ОС/SSH-сервере;
такая интеграционная проверка не является условием завершения003.
