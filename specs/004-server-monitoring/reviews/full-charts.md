# Full-size monitoring graphs — 2026-11-04

User requested proper graphs on the dedicated Monitoring page and explanation
of old component/data discovery. User explicitly prohibits desktop control/app
launch without a new request. No ComputerUse,app launch,real-server reads or UI
captures used in this change. Source-code inspection and fake/unit checks only.

Discovery: rg searches for DeckHistory/C22/history led to001/component-library.md
and lib/ui/deck_history.dart. Compact code limits width270–300,height25; that
variant had been incorrectly used on the page. Production observations follow
linuxMonitoringCommand(/proc/stat,/proc/meminfo,df-Pk-root)→MonitoringOwner→Isar
MonitoringHistoryRecord→HistoryCodec.chart→MonitoringHistoryPanel→sharedC22.
Numbers in actual app are from those retained observations,not synthetic fixtures.
No independent SSH session or external telemetry query was created by this work.

FR427/428,AC423/424→001C22fullSize contract→001R019/004T037→shared part painter and
functional owner projection. Full variant uses available width,readable plot height,
fixed hour UTC axis,0/25/50/75/100% grid,90%threshold,per-metric labels,real-point
hover/tap/keyboard selection and synchronized cursors. Gaps break fill and stroke.
Singleton dots,empty,nullable fields,quality and textual alternative retained.
Owner supplies rangeEnd;no extra sampling. Compact remains an explicit current
variant for compact cards;Monitoring page explicitly requests fullSize.

Source files lib/ui/deck_history.dart,deck_history_full.dart;monitoring_view.dart,
monitoring_owner.dart(owner UTC getter only). Registry C22 and generated catalog
metadata synchronized with tools/generate-component-metadata.py. No dependencies,
collectors,storage schema/format,trust,activation or TTL behavior changed.

Actual checks: output/full-charts-unit-4.log exit0,format380files/0changes,
analyze0issues,boundary90files,732Flutter units,2offlineMCPschema+5toolingPython units.
output/full-charts-components-3.log exit0:130shared tests passed,1opt-in capture
skipped. Dimensions/axis/painter gap/readout interaction checks only synthetic001;
ordinary feature test checks values/quality/owner time/no extra collects,no layout.
Earlier metadata mismatch and test fixture/pointer issues corrected before clean runs.
output/full-charts-scoped-links.log exit0:44links in001/004 allOK.
Earlier exactglobal lychee exits2 due concurrent006missing installation contract,
not a chart-doc error;global check being repeated as006artifacts now appear.
Independent review pending. Fresh EXE build will not launch application.


Final exactglobal lychee output/full-charts-links-review.log exit0:
252total246OK6excluded0errors. Concurrent006link issue resolved when artifact appeared.
Independent reviewer /root/review_full_charts completed read-only report: no findings,
scoped implementation/specification ready; no unresolved confirmed findings.
No implementation changes after that review. R019/T037 complete.

Fresh internal preview EXE build tools/build-release.ps1 -OutputDirectory
output/preview-monitoring completed exit0,output/full-charts-build.log. MaterialIcons
and packaging/import checks performed by build script passed. Artifact
output/preview-monitoring/ServerDeck.exe,SHA256
51bb8b1a262bffeaeee47132e4d46c8d53fbb708ffbd4103c51a73dcd7827cac.
This is a preview artifact for explicitly requested graph feedback,not an installation
or completion of006distribution scope. Application was not launched;ComputerUse and
screenshots not used. No commit/publication. Final evidence/task marker edits only.
