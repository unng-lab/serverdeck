#include "uninstall.h"
#include "pending_update.h"

namespace sd::install {
namespace {
[[noreturn]] void Invalid() { throw updates::Failure("RECOVERY_REQUIRED"); }
void Sid(const std::string& sid, const Files& files) { if (sid != Utf8(files.roots().sid)) Invalid(); }
bool Same(const Installation& a, const Installation& b) { return EncodeInstallation(a) == EncodeInstallation(b); }
void ValidatePending(Files& files) {
  for (unsigned slot = 0; slot < 2; ++slot) {
    const auto owner = updates::PendingPath(slot, L"owner.v1");
    const auto setup = updates::PendingPath(slot, L"ServerDeckSetup.exe");
    const auto catalog = updates::PendingPath(slot, L"catalog.v1");
    if (!files.Exists(owner)) {
      if (files.Exists(setup) || files.Exists(catalog)) Invalid();
    } else {
      const auto consent = updates::DecodePending(files.ReadRecord(owner)); Sid(consent.sid, files);
      if (consent.slot != slot) Invalid();
      if (files.Exists(setup) && !(files.Inspect(setup) == consent.setup)) Invalid();
      if (files.Exists(catalog)) {
        const auto bytes = files.ReadRecord(catalog);
        if (Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()) != consent.catalogHash) Invalid();
      }
    }
  }
  if (files.Exists(L"pending/consent.v1")) Sid(updates::DecodePending(files.ReadRecord(L"pending/consent.v1")).sid, files);
  if (files.Exists(L"pending/tombstone.v1")) Sid(updates::DecodeRetirement(files.ReadRecord(L"pending/tombstone.v1")).consent.sid, files);
  if (files.Exists(L"pending/defer-once.v1")) Sid(updates::DecodeDeferral(files.ReadRecord(L"pending/defer-once.v1")).consent.sid, files);
}
}
RemovalResult RemoveInstallation(Files& files, Lease& lease, Registration& registration,
    const RemovalTicket& ticket, const std::function<void()>& preserveRetry, Checkpoint checkpoint) {
  files.roots().Validate();
  if (!lease.Owns(files.roots(), true)) throw updates::Failure("OWNER_RUNNING");
  EncodeRemovalTicket(ticket); const auto& expected = ticket.target;
  Sid(expected.sid, files); if (!preserveRetry) Invalid();
  Journal journal{ticket.id, Operation::remove, Stage::prepared, expected, expected};
  if (files.Exists(L"journal.v1")) {
    journal = DecodeJournal(files.ReadRecord(L"journal.v1"));
    if (journal.kind != Operation::remove || journal.id != ticket.id || !Same(journal.target, expected)) Invalid();
  } else {
    if (!files.Exists(L"installation.v1") || !Same(DecodeInstallation(files.ReadRecord(L"installation.v1")), expected)) Invalid();
    if (!files.Exists(L"commit.v1")) Invalid();
    const auto commit = files.ReadRecord(L"commit.v1");
    if (Sha256(reinterpret_cast<const uint8_t*>(commit.data()), commit.size()) != ticket.commitHash) Invalid();
  }
  registration.CheckOwnership(); ValidatePending(files);
  if (files.Exists(L"recovery/recovery.v1")) Sid(DecodeRecovery(files.ReadRecord(L"recovery/recovery.v1")).sid, files);
  // Validate/reclaim only the two bounded, SID-owned staging areas. Unknown
  // staging blocks removal before its journal/retry registration is changed.
  files.CleanupStaging();
  files.WriteRecord(L"journal.v1", EncodeJournal(journal));
  preserveRetry(); if (checkpoint) checkpoint("remove-prepared");
  RemovalResult result;
  const auto remove = [&](const std::wstring& path) {
    try { files.Remove(path); if (checkpoint) checkpoint("remove-file"); }
    catch (const std::exception&) { result.remaining.push_back(path); }
  };
  for (unsigned slot = 0; slot < 2; ++slot) {
    const auto setup = updates::PendingPath(slot, L"ServerDeckSetup.exe"), catalog = updates::PendingPath(slot, L"catalog.v1");
    remove(setup); remove(catalog);
    if (!files.Exists(setup) && !files.Exists(catalog)) remove(updates::PendingPath(slot, L"owner.v1"));
  }
  for (const auto* path : {L"ServerDeck.exe", L"ServerDeckSetup.exe", L"ServerDeck.new", L"ServerDeckSetup.new",
      L"ServerDeck.previous", L"ServerDeckSetup.previous", L"recovery/ServerDeckSetup.exe"}) remove(path);
  if (!result.complete()) return result;
  for (const auto* path : {L"pending/consent.v1", L"pending/tombstone.v1", L"pending/defer-once.v1", L"recovery/recovery.v1"}) remove(path);
  if (!result.complete()) return result;
  try { files.CleanupStaging(true); } catch (const std::exception&) { result.remaining.push_back(L"staging"); }
  if (!result.complete()) return result;
  try { registration.RemoveRecoveryLink(); } catch (const std::exception&) { result.remaining.push_back(L"recovery-shortcut"); }
  if (!result.complete()) return result;
  // The durable removal journal remains the authority if metadata deletion or
  // registration cleanup is interrupted. It never authorizes starting runtime.
  remove(L"commit.v1"); remove(L"installation.v1");
  if (!result.complete()) return result;
  try { registration.Remove(); } catch (const std::exception&) { result.remaining.push_back(L"registration"); }
  if (!result.complete()) { preserveRetry(); return result; }
  if (checkpoint) checkpoint("remove-registration");
  remove(L"journal.v1");
  if (!result.complete()) { preserveRetry(); return result; }
  for (const auto* relative : {L"pending/slot0", L"pending/slot1", L"pending", L"recovery", L""}) {
    const auto directory = files.roots().install / relative; RejectReparse(directory);
    if (!RemoveDirectoryW(ExtendedPath(directory).c_str())) {
      const auto code = GetLastError();
      if (code != ERROR_DIR_NOT_EMPTY && code != ERROR_FILE_NOT_FOUND && code != ERROR_PATH_NOT_FOUND) result.remaining.push_back(relative);
    }
  }
  if (!result.complete()) { files.WriteRecord(L"journal.v1", EncodeJournal(journal)); preserveRetry(); }
  return result;
}
}
