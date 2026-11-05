# Bounded artifact transfer — T049

Date: 2026-11-04. Streaming component for T017, not completed download/pending workflow.

## Implemented source

`native/include/artifact_transfer.h` and `native/install/artifact_transfer.cpp` provide
a private request transport, sink and observed-progress interface. A caller supplies
an already authenticated consented Release; this component validates compatibility,
URL policy, size and full SHA256. It streams chunks≤64KiB without buffering the full
setup. Success means the exact signed length/hash matched, not that pending/ready
was published or the PE/resources were validated.

`native/install/update_service.cpp` adds the real WinHTTP artifact adapter and shared
pre-cancel/deadline guards before async Send/Read. Policy is checked before every request;
HTTPS relative/absolute redirects resolve through UrlCombineW and are limited to3.
Header/idle/wall limits are30s/60s/30min; observed Content-Length remains optional and
must match signed size when present. Only HTTP200 supplies artifact bytes; no resume,
application retry, credentials, cookies, auth or TLS bypass. Requests drain final
callbacks before releasing their context/read buffer. CMake adds the OS shlwapi library.

## Actual validation

- Native gate exit0:15/15 unit targets passed. Synthetic transport fixtures exercise
  known/unknown observed length, exact three redirects/fourth refusal, relative/CDN
  transitions, untrusted HTTP/hosts/IP aliases/userinfo/ports/fragments/backslashes,
  truncation/excess bytes/hash mismatch/header mismatch/oversized read count,
  HTTP206/401/500 rejection before sink write, pre/during-stream cancellation, sink IO
  failure, header/idle/wall fake deadlines and request destruction on failures.
- The initial compile exposed an ambiguous fixture helper name, corrected before
  successful checks. A failing denial-code unit also exposed parser INVALID_CATALOG
  leaking through the network boundary; RequireDownloadUrl now consistently reports
  SOURCE_UNTRUSTED for rejected download URLs.
- Flutter Windows release compilation exit0,29.6s, with new native source/link dependency.
- Lychee exit0:258total252OK0errors6excluded2redirects before this evidence file.
- No Dart source changed; previous754 ordinary Flutter tests/format/analyze results
  remain scoped to that unchanged Dart milestone. No repeated Flutter gate is claimed.

Independent fresh read-only `review_artifact_transfer` inspected source, tests, CMake
and the full006 package: «Замечаний не найдено». It confirmed resource/URL/hash/cancel/
lifetime boundaries and readiness of this component for later T017 wiring. Checks
were provided by the primary agent, not independently rerun by that reviewer.

The static adapter review used Microsoft's async close/callback contract. A subsequent
header-boundary question was resolved without code changes: successful
[WinHttpQueryHeaders](https://learn.microsoft.com/en-us/windows/win32/api/winhttp/nf-winhttp-winhttpqueryheaders)
reports string bytes excluding the terminator, so the2049-wchar buffer accepts a
2048-character location while retaining a terminator. This was not a confirmed defect.

No real server, network, application, Explorer, registry, integration/e2e/VM/process-kill
test was run. Disk admission, setup-resource verification, pending publication,
service/channel/runtime wiring and handoff remain open. T049 does not close T017 or
prove end-to-end updating on a clean OS.
