#include "startup_update.h"

namespace sd::install {
namespace {
std::string Code(const std::exception& error) {
  const std::string value(error.what());
  for (const auto* code : {"UPDATE_NOT_CONFIGURED", "NETWORK_UNAVAILABLE", "TIMEOUT", "CANCELLED", "SOURCE_UNTRUSTED",
      "SOURCE_EXPIRED", "SOURCE_CHANGED", "RELEASE_REVOKED", "RELEASE_INCOMPATIBLE", "INVALID_CATALOG", "INVALID_ARTIFACT",
      "DISK_SPACE", "OWNER_RUNNING", "BUSY", "STORAGE_IO", "RECOVERY_REQUIRED"}) if (value == code) return value;
  return "STORAGE_IO";
}
}
StartupAction PrepareGuiStartup(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const Paths& paths, const updates::Version& mappedVersion, StartupInvocation& invocation, HandoffPort& process, bool configured) {
  const auto installed = executor.PrepareStartup();
  if (!(mappedVersion == installed.version)) return StartupAction::relaunch;
  std::optional<updates::PendingUpdate> candidate;
  try {
    candidate = pending.PrepareStartup(lease, installed, configured);
    if (!configured) return StartupAction::host;
    if (!invocation.deferred) pending.ConsumeDeferOnce(lease, [&](const std::string& code) { invocation.deferred = true; invocation.code = code; });
  } catch (const std::exception& error) {
    // A verified complete canonical installation remains usable when only its
    // optional update cache is damaged. The live service reports cache failure;
    // never execute or delete ambiguous pending bytes.
    invocation.deferred = true; invocation.code = Code(error); return StartupAction::host;
  }
  if (!candidate || invocation.deferred) return StartupAction::host;
  try { StartPendingHandoff(lease, paths, candidate->consent.slot, process); return StartupAction::handedOff; }
  catch (const std::exception& error) {
    invocation.deferred = true; invocation.code = Code(error);
    try {
      pending.DeferOnce(lease, candidate->consent, invocation.code, Utf8(Uuid()));
      pending.ConsumeDeferOnce(lease, [&](const std::string& code) { invocation.code = code; });
    } catch (const std::exception&) {
      // This parent is still alive and its invocation latch already prevents
      // another handoff. Optional-cache IO must not block the verified GUI.
      // A new helper invocation still requires durable deferral before relaunch.
    }
    return StartupAction::host;
  }
}
void PrepareUpdateRestart(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const Paths& paths, const updates::Version& mappedVersion, HandoffPort& process) {
  const auto installed = executor.PrepareStartup();
  if (!(installed.version == mappedVersion)) throw updates::Failure("RECOVERY_REQUIRED");
  const auto candidate = pending.PrepareStartup(lease, installed);
  if (!candidate || !(installed.version < candidate->release.version)) throw updates::Failure("SOURCE_CHANGED");
  StartPendingHandoff(lease, paths, candidate->consent.slot, process);
}
bool ApplySelectedPending(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const updates::PendingConsent& expected, const Package& package, const updates::Policy& policy,
    updates::CatalogSource& source, updates::UpdateService::Clock clock, MaintenanceReporter report) {
  if (report) report(MaintenanceStage::recovering);
  const auto candidate = pending.PrepareStartup(lease, executor.PrepareStartup());
  if (!candidate || updates::EncodePending(candidate->consent) != updates::EncodePending(expected)) throw updates::Failure("SOURCE_CHANGED");
  try {
    const std::atomic<bool> cancel{false};
    if (report) report(MaintenanceStage::revalidating);
    const auto release = updates::Revalidate(source, policy, candidate->release, cancel, clock);
    if (report) report(MaintenanceStage::applying);
    executor.Apply(package, true, &release);
    if (report) report(MaintenanceStage::recovering);
    pending.PrepareStartup(lease, executor.PrepareStartup()); return true;
  } catch (const std::exception& error) {
    if (report) report(MaintenanceStage::recovering);
    return ResolvePendingFailure(executor, pending, lease, expected, error);
  }
}
bool ResolvePendingFailure(Executor& executor, updates::PendingStore& pending, Lease& lease,
    const updates::PendingConsent& expected, const std::exception& error) {
  const auto current = executor.PrepareStartup();
  if (!(current.version < expected.version)) {
    try { pending.PrepareStartup(lease, current); } catch (const std::exception&) { /* Only update-cache cleanup failed; canonical commit is verified. */ }
    return true;
  }
  pending.DeferOnce(lease, expected, Code(error), Utf8(Uuid())); return false;
}
}
