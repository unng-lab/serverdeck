# Logs: behavioral research

Read-only source: https://github.com/unng-lab/logs/tree/a7bf7f8f0c4d5d37be6a54119eaf70a1248520b9
Reviewed 2026-10-05: README, pubspec, SSH service, server/config/metrics models,
server repositories, log provider, detail controller/screens and selected test
sources. No source was changed or copied, and no tests/application were executed.
Findings describe code behavior, not verified runtime guarantees.

| Observed behavior | Business need in ServerDeck |
| --- | --- |
| Multiple saved SSH servers, names, ports, password/key authentication | BR-S01: user manages several servers from one desktop |
| journalctl JSON history + follow | BR-L01: inspect recent history and watch new events |
| Default100 initial lines, command clamp1..1000 | BR-L02: choose bounded initial history |
| Per-server bounded buffer500, subscription retained outside detail screen | BR-L03: switching screens preserves a bounded session view |
| Select service, case-insensitive message search, priority-based severity | BR-L04: find the relevant software's messages quickly |
| Local timestamp, raw journal fields, realtime microsecond timestamp, fresh marker | BR-L05: inspect timing and structured event details |
| Desktop text selection and reverse list | BR-L06: copy useful diagnostics and follow newest entries |
| Service status/start/stop/restart actions | BR-S02: operate a selected service and observe the result |
| Host CPU/RAM and service MainPID metrics | BR-M01: assess basic host/service activity |

Limits that the new design must address:

- Discovery currently asks only for running units and excludes @ instance units;
  stopped/failed/instance services must be discoverable in ServerDeck. Running
  services are not the complete list of installed software.
- ServerConfig serializes password/privateKey/passphrase; repository writes the
  JSON to SharedPreferences. Do not preserve this credential storage design.
- Reviewed connection construction does not supply an explicit host-key verifier.
  New client must implement known-host pinning and mismatch denial.
- serviceArgs are interpolated into a shell command. New adapters validate source
  identifiers and pass properly encoded arguments; never accept arbitrary commands
  from synchronized metadata or recipe labels.
- Invalid journal JSON is silently skipped. New UI reports parse/drop counts and
  distinguishes no events, permission denial, disconnection and unsupported source.
- No installation-job engine, software-version registry or synchronization backend
  was found in the reviewed source. Disk/network metrics and durable cursor resume
  are new proposed requirements, not inherited implemented functionality.

The new spec distinguishes explicit human scope, extracted existing behavior and
proposed design choices. Source license was not established; reuse code only after
a separate license review.
