#pragma once
#include "maintenance_handoff.h"
#include "update_service.h"
#include "maintenance_status.h"

namespace sd::install {
enum class StartupAction { host, handedOff, relaunch };
struct StartupInvocation { bool deferred = false; std::string code; };
StartupAction PrepareGuiStartup(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const Paths& paths, const updates::Version& mappedVersion, StartupInvocation& invocation, HandoffPort& process, bool configured = true);
// Post-host restart only: failure is reported to native retry/cancel, never host fallback.
void PrepareUpdateRestart(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const Paths& paths, const updates::Version& mappedVersion, HandoffPort& process);
// Called only after a validated helper has acknowledged readiness and observed
// its actual parent terminate. False means verified old installation + deferOnce.
bool ApplySelectedPending(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const updates::PendingConsent& expected, const Package& package, const updates::Policy& policy,
    updates::CatalogSource& source, updates::UpdateService::Clock clock = {}, MaintenanceReporter report = {});
bool ResolvePendingFailure(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const updates::PendingConsent& expected, const std::exception& error);
}
