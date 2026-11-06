#include "pending_update.h"
#include "update_service.h"
#include "startup_update.h"
#include "build_identity.h"
#include "setup_package.h"
#include <bcrypt.h>
#include <algorithm>
#include <cstring>
#include <fstream>
#include <iostream>

namespace {
void Require(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
template<class F> void Reject(F action, const char* code) {
  try { action(); } catch (const sd::updates::Failure& error) { Require(std::string(error.what()) == code, "wrong rejection"); return; }
  throw std::runtime_error("invalid pending operation accepted");
}
struct Interrupted {};
struct Signer {
  BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_KEY_HANDLE key = nullptr;
  Signer() {
    Require(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_ECDSA_P256_ALGORITHM, nullptr, 0) >= 0, "algorithm");
    Require(BCryptGenerateKeyPair(algorithm, &key, 256, 0) >= 0 && BCryptFinalizeKeyPair(key, 0) >= 0, "key");
  }
  ~Signer() { if (key) BCryptDestroyKey(key); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
  static std::string Hex(const uint8_t* bytes, size_t size) {
    std::string result; constexpr char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < size; ++i) { result += hex[bytes[i] >> 4]; result += hex[bytes[i] & 15]; }
    return result;
  }
  sd::updates::Policy Policy() {
    uint8_t blob[72]{}; ULONG length = 0;
    Require(BCryptExportKey(key, nullptr, BCRYPT_ECCPUBLIC_BLOB, blob, 72, &length, 0) >= 0 && length == 72, "public");
    return sd::updates::ParsePolicy("{\"schema\":1,\"endpoint\":\"https://updates.example/stable\",\"downloadHosts\":[\"assets.example\"],"
      "\"storeFormat\":2,\"keys\":[{\"id\":\"unit\",\"p256\":\"" + Hex(blob + 8, 64) + "\"}]}");
  }
  std::string Catalog(const sd::updates::Release& release, bool staticCatalog = false) {
    const auto header = staticCatalog ? "SDRELEASES002\n99990\n1\n" : "SDRELEASES001\n99990\n100100\n1\n";
    const auto bytes = header + release.version.text + "\nwindows-x64\n1\n2\n99900\n" +
      std::to_string(release.setupSize) + '\n' + release.setupHash + '\n' + std::to_string(release.appSize) + '\n' +
      release.appHash + '\n' + release.url + "\n0KLQtdGB0YI=\n";
    const auto hash = sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
    uint8_t digest[32]{}; for (size_t i = 0; i < 32; ++i) digest[i] = static_cast<uint8_t>(std::stoul(hash.substr(i * 2, 2), nullptr, 16));
    uint8_t signature[64]{}; ULONG length = 0;
    Require(BCryptSignHash(key, nullptr, digest, 32, signature, 64, &length, 0) >= 0 && length == 64, "signature");
    return std::string(staticCatalog ? "SDCATALOG002\nunit\n" : "SDCATALOG001\nunit\n") + Hex(signature, 64) + '\n' + bytes;
  }
};
struct Transport : sd::updates::ArtifactTransport {
  std::string body; int requests = 0;
  struct Request : sd::updates::ArtifactRequest {
    std::string body; size_t offset = 0;
    explicit Request(std::string bytes) : body(std::move(bytes)) {}
    sd::updates::ArtifactHeaders Start(uint64_t, const std::atomic<bool>&) override { return {200, {}, {}}; }
    size_t Read(uint8_t* out, size_t capacity, uint64_t, const std::atomic<bool>&) override {
      const auto count = std::min(capacity, body.size() - offset); if (count) std::memcpy(out, body.data() + offset, count);
      offset += count; return count;
    }
  };
  std::unique_ptr<sd::updates::ArtifactRequest> Open(const std::string&) override { ++requests; return std::make_unique<Request>(body); }
};
sd::updates::Release MakeRelease(const char* version, const std::string& setup) {
  sd::updates::Release result; result.version = sd::updates::ParseVersion(version); result.platform = "windows-x64";
  result.bootstrapAbi = 1; result.storeFormat = 2; result.published = 99900; result.notes = "Тест";
  result.setupSize = setup.size(); result.setupHash = sd::Sha256(reinterpret_cast<const uint8_t*>(setup.data()), setup.size());
  const std::string app = "synthetic app"; result.appSize = app.size();
  result.appHash = sd::Sha256(reinterpret_cast<const uint8_t*>(app.data()), app.size()); result.url = "https://assets.example/setup.exe";
  return result;
}
struct Registration : sd::install::Registration {
  std::optional<sd::install::Installation> record;
  void CheckOwnership() override {}
  void SetRecoveryLink() override {}
  void Set(const sd::install::Installation& value) override { record = value; }
  bool Matches(const sd::install::Installation& value) override {
    return record && record->sid == value.sid && record->version == value.version && record->app == value.app && record->setup == value.setup;
  }
  void Remove() override { record.reset(); }
  void RemoveRecoveryLink() override {}
};
struct Launch : sd::install::HandoffPort {
  DWORD result = WAIT_OBJECT_0; int calls = 0;
  std::unique_ptr<sd::Handle> Spawn(const std::filesystem::path&, const std::wstring&, const std::array<HANDLE, 5>&) override {
    ++calls; HANDLE process = nullptr;
    Require(DuplicateHandle(GetCurrentProcess(), GetCurrentProcess(), GetCurrentProcess(), &process, SYNCHRONIZE, FALSE, 0) != FALSE, "fake process handle");
    return std::make_unique<sd::Handle>(process);
  }
  DWORD WaitReady(HANDLE, HANDLE, DWORD timeout) override { Require(timeout == 3000, "startup readiness deadline"); return result; }
};
struct Source : sd::updates::CatalogSource {
  std::string bytes, failure; int calls = 0;
  std::string Fetch(const std::atomic<bool>&) override { ++calls; if (!failure.empty()) throw sd::updates::Failure(failure.c_str()); return bytes; }
};
std::vector<uint8_t> ResourceFixture() {
  std::vector<uint8_t> bytes(1536);
  const auto put = [&](size_t offset, const auto& value) { std::memcpy(bytes.data() + offset, &value, sizeof(value)); };
  IMAGE_DOS_HEADER dos{}; dos.e_magic = IMAGE_DOS_SIGNATURE; dos.e_lfanew = 128; put(0, dos);
  const DWORD signature = IMAGE_NT_SIGNATURE; put(128, signature);
  IMAGE_FILE_HEADER file{}; file.Machine = IMAGE_FILE_MACHINE_AMD64; file.NumberOfSections = 1; file.SizeOfOptionalHeader = sizeof(IMAGE_OPTIONAL_HEADER64); put(132, file);
  IMAGE_OPTIONAL_HEADER64 optional{}; optional.Magic = IMAGE_NT_OPTIONAL_HDR64_MAGIC; optional.SizeOfHeaders = 512;
  optional.NumberOfRvaAndSizes = IMAGE_NUMBEROF_DIRECTORY_ENTRIES; optional.DataDirectory[IMAGE_DIRECTORY_ENTRY_RESOURCE] = {4096, 1024}; put(152, optional);
  IMAGE_SECTION_HEADER section{}; section.VirtualAddress = 4096; section.PointerToRawData = 512; section.SizeOfRawData = 1024; put(392, section);
  IMAGE_RESOURCE_DIRECTORY directory{}; directory.NumberOfIdEntries = 1; put(512, directory);
  IMAGE_RESOURCE_DIRECTORY_ENTRY entry{}; entry.Name = 10; entry.DataIsDirectory = 1; entry.OffsetToDirectory = 32; put(528, entry);
  directory = {}; directory.NumberOfNamedEntries = 1; put(544, directory);
  entry = {}; entry.NameIsString = 1; entry.NameOffset = 128; entry.DataIsDirectory = 1; entry.OffsetToDirectory = 64; put(560, entry);
  directory = {}; directory.NumberOfIdEntries = 1; put(576, directory);
  entry = {}; entry.Name = 1033; entry.OffsetToData = 96; put(592, entry);
  const std::string text = "SDBUILD001\n0.2.0\n";
  IMAGE_RESOURCE_DATA_ENTRY data{}; data.OffsetToData = 4096 + 192; data.Size = static_cast<DWORD>(text.size()); put(608, data);
  const std::wstring name = L"SERVERDECK_BUILD_V1"; const WORD count = static_cast<WORD>(name.size()); put(640, count);
  std::memcpy(bytes.data() + 642, name.data(), name.size() * sizeof(wchar_t)); std::memcpy(bytes.data() + 704, text.data(), text.size());
  return bytes;
}
}
int main() {
  using namespace sd::updates;
  std::filesystem::path root;
  try {
    wchar_t temp[32768]{}; Require(GetTempPathW(32768, temp) != 0, "temp");
    root = std::filesystem::path(temp) / (L"ServerDeckPendingUnit-" + sd::Uuid()); sd::SecureDirectory(root);
    Signer signer; const auto policy = signer.Policy();
    const std::string oldBytes = "verified old synthetic setup", newBytes(131073, 'n');
    const auto old = MakeRelease("0.2.0", oldBytes), next = MakeRelease("0.3.0", newBytes);
    const auto oldCatalog = signer.Catalog(old), newCatalog = signer.Catalog(next);
    {
      const auto scenario = root / L"static-catalog"; sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, [](const std::filesystem::path&, const Version&, const sd::install::Identity&) {});
      Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto catalog = signer.Catalog(old, true);
      const auto ready = store.Download(old, catalog, 100000 + 365 * 86400, transport, cancel,
        [](const PendingWrite& write) { write([] {}); });
      const auto restored = store.Restore();
      Require(restored && restored->consent.id == ready.consent.id && restored->catalog == catalog &&
        SameIdentity(restored->release, old), "static catalog pending restoration failed");
    }
    const auto validator = [](const std::filesystem::path&, const Version&, const sd::install::Identity&) {};
    const PendingCommit commit = [](const PendingWrite& write) { write([] {}); };
    for (const auto* stop : {"none", "pending-owner", "pending-setup", "pending-catalog", "pending-verified", "pending-committed"}) {
      const auto scenario = root / sd::Wide(stop); sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      sd::SecureDirectory(paths.data); { std::ofstream sentinel(paths.data / L"keep"); sentinel << "retain"; }
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      auto first = store.Download(old, oldCatalog, 100000, transport, cancel, commit);
      Require(DecodePending(EncodePending(first.consent)).setup == first.consent.setup, "pending codec");
      Reject([&] { DecodePending(EncodePending(first.consent) + "x"); }, "RECOVERY_REQUIRED");
      {
        sd::install::Lease maintenance(paths, false); Require(store.Read(maintenance)->release.version == old.version, "initial ready");
        Reject([&] { store.CleanupInactive(maintenance, first.consent.slot); }, "BUSY");
      }
      PendingStore injected(paths, policy, validator, [&](const char* point) { if (std::string(stop) == point) throw Interrupted{}; });
      transport.body = newBytes;
      bool preferenceWritten = false;
      try { injected.Download(next, newCatalog, 100000, transport, cancel, commit, [&](uint64_t, std::optional<uint64_t>) {
        if (!preferenceWritten) {
          auto prefs = MakeFilePreferenceStore(paths); Preferences value; value.enabled = false; prefs->Save(value); preferenceWritten = true;
        }
      }); } catch (const Interrupted&) {}
      {
        sd::install::Lease maintenance(paths, false);
        const auto active = store.Read(maintenance); const bool committed = std::string(stop) == "none" || std::string(stop) == "pending-committed";
        Require(active && active->release.version == (committed ? next.version : old.version), "interruption lost ready");
      }
      store.Download(next, newCatalog, 100000, transport, cancel, commit);
      {
        sd::install::Lease maintenance(paths, false); Require(store.Read(maintenance)->release.version == next.version, "replacement retry");
      }
      Require(std::filesystem::file_size(paths.data / L"keep") == 6, "data sentinel changed");
      if (std::string(stop) != "pending-owner") Require(preferenceWritten, "download blocked preferences");
    }
    {
      const auto scenario = root / L"published-cleanup-fault"; sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      std::unique_ptr<sd::Handle> blocker; bool notified = false;
      const PendingCommit fault = [&](const PendingWrite& write) {
        write([&] {
          notified = true;
          // A synthetic open file denies deletion of the already-flushed marker
          // after pointer rename, exercising the actual adapter failure boundary.
          blocker = std::make_unique<sd::Handle>(CreateFileW(sd::ExtendedPath(paths.install / L".stage-owner.v1").c_str(),
            GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
          Require(blocker->valid(), "marker blocker");
        });
      };
      const auto ready = store.Download(old, oldCatalog, 100000, transport, cancel, fault);
      Require(notified && blocker && blocker->valid() && std::filesystem::exists(paths.install / L".stage-owner.v1"), "post-publish cleanup fault not injected");
      blocker.reset();
      sd::install::Lease maintenance(paths, false);
      Require(store.Read(maintenance)->consent.id == ready.consent.id, "published pointer lost after cleanup failure");
      sd::install::Files files(paths); files.CleanupStaging();
      Require(!std::filesystem::exists(paths.install / L".stage-owner.v1"), "committed stage could not be reclaimed");
    }
    {
      const auto scenario = root / L"cancel-and-trust"; sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto first = store.Download(old, oldCatalog, 100000, transport, cancel, commit);
      transport.body = newBytes;
      Reject([&] { store.Download(next, newCatalog, 100000, transport, cancel, commit, [&](uint64_t bytes, std::optional<uint64_t>) { if (bytes) cancel = true; }); }, "CANCELLED");
      cancel = false;
      const PendingCommit cancelGate = [&](const PendingWrite&) { cancel = true; throw Failure("CANCELLED"); };
      Reject([&] { store.Download(next, newCatalog, 100000, transport, cancel, cancelGate); }, "CANCELLED"); cancel = false;
      Reject([&] { store.Download(next, oldCatalog, 100000, transport, cancel, commit); }, "RECOVERY_REQUIRED");
      const auto requests = transport.requests;
      Reject([&] { store.Download(next, newCatalog, 100101, transport, cancel, commit); }, "SOURCE_EXPIRED");
      Require(requests == transport.requests, "expired consent downloaded");
      sd::install::Files files(paths); const auto inactive = 1 - first.consent.slot;
      const std::string foreign = "foreign bytes"; bool inserted = false;
      Reject([&] { store.Download(next, newCatalog, 100000, transport, cancel, commit, [&](uint64_t bytes, std::optional<uint64_t>) {
        if (bytes && !inserted) {
          files.WriteArtifact(PendingPath(inactive, L"ServerDeckSetup.exe"), reinterpret_cast<const uint8_t*>(foreign.data()), foreign.size()); inserted = true;
        }
      }); }, "RECOVERY_REQUIRED");
      sd::install::Lease maintenance(paths, false); Require(store.Read(maintenance)->consent.id == first.consent.id, "cancel replaced prior ready");
      Reject([&] { store.CleanupInactive(maintenance, inactive); }, "RECOVERY_REQUIRED");
      Require(files.Inspect(PendingPath(inactive, L"ServerDeckSetup.exe")).size == foreign.size(), "foreign file deleted");
    }
    for (const auto* mode : {"consumed", "superseded", "changed"}) {
      const auto scenario = root / sd::Wide(std::string("retire-") + mode); sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto ready = store.Download(old, oldCatalog, 100000, transport, cancel, commit);
      sd::install::Installation installed{ready.consent.sid, ready.consent.version, ready.consent.app, ready.consent.setup, {}, {}};
      if (std::string(mode) == "superseded") installed.version = next.version;
      if (std::string(mode) == "changed") installed.setup.hash.assign(64, 'c');
      sd::install::Files files(paths);
      {
        sd::Handle mapped(CreateFileW(sd::ExtendedPath(files.Path(PendingPath(ready.consent.slot, L"ServerDeckSetup.exe"))).c_str(),
          GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
        Require(mapped.valid(), "mapped helper fixture"); sd::install::Lease lease(paths, true);
        Require(!store.PrepareStartup(lease, installed) && !files.Exists(L"pending/consent.v1") && files.Exists(L"pending/tombstone.v1"),
          "mapped retired helper remained eligible");
        Require(!store.Read(lease), "retired pointer restored ready");
        Require(store.Notice().code == (std::string(mode) == "changed" ? "SOURCE_CHANGED" : ""), "retirement notice");
        Require(!store.CleanupRetired(lease), "mapped helper falsely cleaned");
      }
      {
        sd::install::Lease lease(paths, true);
        Require(store.CleanupRetired(lease) && !files.Exists(PendingPath(ready.consent.slot, L"ServerDeckSetup.exe")), "retired helper not reclaimed after exit");
        if (std::string(mode) == "changed") {
          installed.version = next.version;
          Require(!store.PrepareStartup(lease, installed) && store.Notice().code.empty() && !files.Exists(L"pending/tombstone.v1"),
            "newer manual install retained old same-version mismatch");
        }
      }
      transport.body = newBytes; const auto newer = store.Download(next, newCatalog, 100000, transport, cancel, commit);
      {
        sd::install::Lease lease(paths, false);
        files.WriteRecord(L"pending/tombstone.v1", EncodeRetirement({ready.consent, mode}));
        Require(store.CleanupRetired(lease) && store.Read(lease)->consent.id == newer.consent.id && store.Notice().code.empty(),
          "stale retirement deleted/suppressed new pending identity");
      }
    }
    for (const auto* point : {"pending-retired", "retired-detached", "retired-files-cleaned"}) {
      const auto scenario = root / sd::Wide(point); sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto ready = store.Download(old, oldCatalog, 100000, transport, cancel, commit);
      const sd::install::Installation installed{ready.consent.sid, ready.consent.version, ready.consent.app, ready.consent.setup, {}, {}};
      sd::install::Lease lease(paths, true); sd::install::Files files(paths);
      files.WriteRecord(L"installation.v1", sd::install::EncodeInstallation(installed)); files.WriteRecord(L"commit.v1", "unchanged proof sentinel\n");
      PendingStore injected(paths, policy, validator, [&](const char* stage) { if (std::string(stage) == point) throw Interrupted{}; });
      bool interrupted = false; try { injected.PrepareStartup(lease, installed); } catch (const Interrupted&) { interrupted = true; }
      Require(interrupted && !store.Read(lease), "interruption restored retired readiness");
      Require(!store.PrepareStartup(lease, installed) && !files.Exists(L"pending/consent.v1") &&
        files.ReadRecord(L"installation.v1") == sd::install::EncodeInstallation(installed) && files.ReadRecord(L"commit.v1") == "unchanged proof sentinel\n",
        "retirement recovery changed installation/commit");
    }
    {
      const auto scenario = root / L"defer-once"; sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto ready = store.Download(old, oldCatalog, 100000, transport, cancel, commit); const auto attempt = sd::Utf8(sd::Uuid());
      {
        sd::install::Lease lease(paths, true); sd::install::Files files(paths);
        store.DeferOnce(lease, ready.consent, "NETWORK_UNAVAILABLE", attempt);
        const auto encoded = files.ReadRecord(L"pending/defer-once.v1");
        Require(DecodeDeferral(encoded).attempt == attempt && !DecodeDeferral(encoded).consumed, "deferral codec");
        Reject([&] { DecodeDeferral(encoded + "extra\n"); }, "RECOVERY_REQUIRED");
        Reject([&] { EncodeDeferral({ready.consent, attempt, "secret arbitrary text", false}); }, "RECOVERY_REQUIRED");
        int latches = 0;
        Require(store.ConsumeDeferOnce(lease, [&](const std::string& code) { Require(code == "NETWORK_UNAVAILABLE", "code"); ++latches; }), "deferral not consumed");
        Require(!store.ConsumeDeferOnce(lease, [&](const std::string&) { ++latches; }) && latches == 1, "deferral repeated across invocations");
        Require(store.Read(lease)->consent.id == ready.consent.id && store.Notice().code == "NETWORK_UNAVAILABLE", "fallback lost ready bytes/status");
        store.DeferOnce(lease, ready.consent, "TIMEOUT", attempt); bool invocationDeferred = false;
        PendingStore injected(paths, policy, validator, [](const char* stage) { if (std::string(stage) == "defer-consumed") throw Interrupted{}; });
        try { injected.ConsumeDeferOnce(lease, [&](const std::string&) { invocationDeferred = true; }); } catch (const Interrupted&) {}
        Require(invocationDeferred && !store.ConsumeDeferOnce(lease, [](const std::string&) {}), "startup retry lost invocation defer latch");
        auto unrelated = ready.consent; unrelated.id = sd::Utf8(sd::Uuid());
        Reject([&] { store.DeferOnce(lease, unrelated, "TIMEOUT", attempt); }, "SOURCE_CHANGED");
        store.DeferOnce(lease, ready.consent, "TIMEOUT", attempt);
      }
      transport.body = newBytes; const auto newer = store.Download(next, newCatalog, 100000, transport, cancel, commit);
      {
        sd::install::Lease lease(paths, true); bool skipped = false;
        Require(!store.ConsumeDeferOnce(lease, [&](const std::string&) { skipped = true; }) && !skipped &&
          store.Read(lease)->consent.id == newer.consent.id && store.Notice().code.empty(), "old fallback skipped replacement consent");
        sd::install::Files files(paths); auto foreign = ready.consent; foreign.sid = "S-1-5-18";
        files.WriteRecord(L"pending/defer-once.v1", EncodeDeferral({foreign, attempt, "TIMEOUT", false}));
        Reject([&] { store.Read(lease); }, "RECOVERY_REQUIRED");
      }
    }
    {
      const auto scenario = root / L"retirement-owner-mismatch"; sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      PendingStore store(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto ready = store.Download(old, oldCatalog, 100000, transport, cancel, commit);
      const sd::install::Installation installed{ready.consent.sid, ready.consent.version, ready.consent.app, ready.consent.setup, {}, {}};
      sd::install::Lease lease(paths, true); sd::install::Files files(paths); auto foreign = ready.consent; foreign.id = sd::Utf8(sd::Uuid());
      files.WriteRecord(PendingPath(ready.consent.slot, L"owner.v1"), EncodePending(foreign));
      Reject([&] { store.PrepareStartup(lease, installed); }, "RECOVERY_REQUIRED");
      Require(files.ReadRecord(L"pending/consent.v1") == EncodePending(ready.consent) && !files.Exists(L"pending/tombstone.v1") &&
        files.Exists(PendingPath(ready.consent.slot, L"ServerDeckSetup.exe")), "invalid owner retired consent or deleted files");
      const auto retirement = EncodeRetirement({ready.consent, "consumed"});
      Require(DecodeRetirement(retirement).consent.id == ready.consent.id, "retirement codec");
      Reject([&] { DecodeRetirement(retirement + "\n"); }, "RECOVERY_REQUIRED");
      Reject([&] { EncodeRetirement({ready.consent, "unknown"}); }, "RECOVERY_REQUIRED");
    }
    Require(sd::install::DecodeBuildVersion("SDBUILD001\n0.2.0\n").text == "0.2.0", "mapped build version codec");
    Require(sd::install::ReadBuildVersion(GetModuleHandleW(nullptr)).text == "9.8.12" &&
      sd::install::ReadFileBuildVersion(sd::install::ModuleFile()).text == "9.8.12" &&
      !sd::install::ReadEmbeddedPolicy(GetModuleHandleW(nullptr)), "resource-only build identity mapping");
    const auto image = ResourceFixture();
    Require(sd::install::ParseRawResource(image.data(), image.size(), L"SERVERDECK_BUILD_V1", 128) == std::optional<std::string>{"SDBUILD001\n0.2.0\n"} &&
      !sd::install::ParseRawResource(image.data(), image.size(), L"SERVERDECK_TRUST_V1", 8192), "raw resource fixture");
    for (const auto offset : {size_t(0), size_t(60), size_t(132), size_t(152), size_t(212), size_t(260), size_t(280), size_t(524), size_t(560), size_t(608)}) {
      auto bad = image; std::fill(bad.begin() + offset, bad.begin() + offset + 4, uint8_t{255});
      Reject([&] { sd::install::ParseRawResource(bad.data(), bad.size(), L"SERVERDECK_BUILD_V1", 128); }, "INVALID_ARTIFACT");
    }
    Reject([&] { sd::install::ParseRawResource(image.data(), 64, L"SERVERDECK_BUILD_V1", 128); }, "INVALID_ARTIFACT");
    Require(sd::install::DecodeBuildVersion("SDBUILD001\n0.1.1\n").text == "0.1.1", "stable mapped build codec");
    for (const auto* invalid : {"SDBUILD001\n0.2\n", "SDBUILD001\n0.2.0\nextra\n", "SDBUILD001\n0.2.0\r\n"})
      Reject([&] { sd::install::DecodeBuildVersion(invalid); }, "INVALID_ARTIFACT");
    for (const auto* scenarioName : {"restart-ready", "restart-timeout", "restart-invalid", "gui-ready", "gui-unconfigured", "gui-timeout", "gui-timeout-defer-io", "gui-timeout-defer-checkpoint", "gui-bad-cache", "helper-offline", "helper-invalid",
        "helper-success", "helper-stale", "helper-registered", "helper-committed"}) {
      const auto scenario = root / sd::Wide(scenarioName); sd::SecureDirectory(scenario);
      const sd::install::Paths paths{scenario / L"install", scenario / L"data", scenario / L"programs", sd::UserSid()};
      const std::string app = "synthetic app", initialSetup = "initial installed setup";
      const sd::install::Package baseline{ParseVersion("0.1.0"), {reinterpret_cast<const uint8_t*>(app.data()), app.size()},
        {reinterpret_cast<const uint8_t*>(initialSetup.data()), initialSetup.size()}};
      const sd::install::Package candidate{old.version, baseline.app, {reinterpret_cast<const uint8_t*>(oldBytes.data()), oldBytes.size()}};
      Registration registration; sd::install::Files files(paths);
      { sd::install::Lease lease(paths, true); sd::install::Executor executor(files, lease, registration, validator); executor.Apply(baseline, true); }
      { std::ofstream data(paths.data / L"startup-data-sentinel", std::ios::binary); data << "unchanged user data"; }
      PendingStore pending(paths, policy, validator); Transport transport; transport.body = oldBytes; std::atomic<bool> cancel{false};
      const auto ready = pending.Download(old, oldCatalog, 100000, transport, cancel, commit);
      sd::install::Lease lease(paths, true); sd::install::Executor executor(files, lease, registration, validator);
      Launch process; sd::install::StartupInvocation invocation; const std::string mode(scenarioName);
      if (mode == "restart-ready" || mode == "restart-timeout" || mode == "restart-invalid") {
        if (mode == "restart-invalid") {
          files.WriteRecord(PendingPath(ready.consent.slot, L"owner.v1"), "invalid ownership\n");
          Reject([&] { sd::install::PrepareUpdateRestart(executor, pending, lease, paths, baseline.version, process); }, "RECOVERY_REQUIRED");
          Require(!process.calls, "invalid restart spawned helper");
        } else {
          if (mode == "restart-timeout") {
            process.result = WAIT_TIMEOUT;
            Reject([&] { sd::install::PrepareUpdateRestart(executor, pending, lease, paths, baseline.version, process); }, "TIMEOUT");
            Require(lease.Owns(paths, true) && files.Exists(L"pending/consent.v1"), "restart failure lost owner/consent");
            process.result = WAIT_OBJECT_0;
          }
          const auto before = process.calls;
          sd::install::PrepareUpdateRestart(executor, pending, lease, paths, baseline.version, process);
          Require(process.calls == before + 1 && executor.Current()->version == baseline.version && lease.Owns(paths, true), "restart mutated installation or lost owner");
        }
      } else if (mode == "gui-ready") {
        Require(sd::install::PrepareGuiStartup(executor, pending, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::handedOff &&
          process.calls == 1 && executor.Current()->version == baseline.version, "parent entered host or mutated before helper");
      } else if (mode == "gui-unconfigured") {
        PendingStore unconfigured(paths, Policy{}, validator);
        Require(sd::install::PrepareGuiStartup(executor, unconfigured, lease, paths, baseline.version, invocation, process, false) == sd::install::StartupAction::host &&
          !process.calls && files.Exists(L"pending/consent.v1"), "unconfigured build tried pending helper/network or lost consent");
      } else if (mode == "gui-bad-cache") {
        files.WriteRecord(PendingPath(ready.consent.slot, L"owner.v1"), "invalid ownership\n");
        Require(sd::install::PrepareGuiStartup(executor, pending, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::host &&
          invocation.deferred && invocation.code == "RECOVERY_REQUIRED" && !process.calls && executor.Current()->version == baseline.version &&
          files.Exists(PendingPath(ready.consent.slot, L"ServerDeckSetup.exe")), "optional cache corruption blocked verified app or erased unknown bytes");
      } else if (mode == "gui-timeout-defer-io" || mode == "gui-timeout-defer-checkpoint") {
        process.result = WAIT_TIMEOUT;
        const auto defer = L"pending/defer-once.v1";
        files.WriteRecord(defer, EncodeDeferral({ready.consent, sd::Utf8(sd::Uuid()), "TIMEOUT", true}));
        std::unique_ptr<sd::Handle> locked;
        if (mode == "gui-timeout-defer-io") {
          locked = std::make_unique<sd::Handle>(CreateFileW(sd::ExtendedPath(files.Path(defer)).c_str(), GENERIC_READ,
            FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr)); Require(locked->valid(), "defer IO fixture");
        }
        int faults = 0;
        PendingStore failing(paths, policy, validator, [&](const char* stage) {
          if (mode == "gui-timeout-defer-checkpoint" && std::string(stage) == "defer-written") { ++faults; throw Failure("STORAGE_IO"); }
        });
        for (int attempt = 0; attempt < 2; ++attempt)
          Require(sd::install::PrepareGuiStartup(executor, failing, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::host &&
            invocation.deferred && process.calls == 1 && executor.Current()->version == baseline.version,
            "optional deferral failure blocked verified GUI or repeated helper");
        Require(mode != "gui-timeout-defer-checkpoint" || faults == 1, "deferral checkpoint not exercised");
      } else if (mode == "gui-timeout") {
        process.result = WAIT_TIMEOUT;
        Require(sd::install::PrepareGuiStartup(executor, pending, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::host &&
          invocation.deferred && pending.Read(lease) && pending.Notice().code == "TIMEOUT", "timeout did not fall back to old installation");
        Require(sd::install::PrepareGuiStartup(executor, pending, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::host &&
          process.calls == 1, "startup retry repeated failed handoff");
      } else {
        Source source; source.bytes = signer.Catalog(old, true);
        std::vector<sd::install::MaintenanceStage> stages;
        const auto report = [&](sd::install::MaintenanceStage stage) { stages.push_back(stage); };
        if (mode == "helper-offline") {
          source.failure = "NETWORK_UNAVAILABLE";
          Require(!sd::install::ApplySelectedPending(executor, pending, lease, ready.consent, candidate, policy, source, {}, report) &&
            executor.Current()->version == baseline.version && source.calls == 1, "offline helper changed installation");
          Require(stages == std::vector<sd::install::MaintenanceStage>{sd::install::MaintenanceStage::recovering,
            sd::install::MaintenanceStage::revalidating, sd::install::MaintenanceStage::recovering}, "offline helper falsely reported applying");
          Require(sd::install::PrepareGuiStartup(executor, pending, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::host &&
            invocation.deferred && !process.calls && pending.Read(lease), "fallback invocation looped or lost consent");
          sd::install::StartupInvocation ordinaryLaunch;
          Require(sd::install::PrepareGuiStartup(executor, pending, lease, paths, baseline.version, ordinaryLaunch, process) == sd::install::StartupAction::handedOff &&
            process.calls == 1, "next ordinary launch could not retry");
        } else if (mode == "helper-invalid") {
          const Failure error("INVALID_ARTIFACT");
          Require(!sd::install::ResolvePendingFailure(executor, pending, lease, ready.consent, error) &&
            executor.Current()->version == baseline.version && pending.Read(lease) && pending.Notice().code == "INVALID_ARTIFACT",
            "post-parent validation failure failed to preserve old install/status");
        } else if (mode == "helper-registered" || mode == "helper-committed") {
          const auto point = mode == "helper-registered" ? "registered" : "committed";
          sd::install::Executor interrupted(files, lease, registration, validator, [&](const char* stage) { if (std::string(stage) == point) throw Interrupted{}; });
          bool stopped = false;
          try { sd::install::ApplySelectedPending(interrupted, pending, lease, ready.consent, candidate, policy, source); } catch (const Interrupted&) { stopped = true; }
          const auto recovered = executor.PrepareStartup();
          Require(stopped && recovered.version == old.version && recovered.consumedVersion == old.version.text && recovered.consumedSetupHash == old.setupHash &&
            !pending.PrepareStartup(lease, recovered) && source.calls == 1, "interrupted committed apply lost consumption or rolled back");
        } else if (mode == "helper-stale") {
          auto stale = ready.consent; stale.id = sd::Utf8(sd::Uuid());
          Reject([&] { sd::install::ApplySelectedPending(executor, pending, lease, stale, candidate, policy, source); }, "SOURCE_CHANGED");
          Require(!source.calls && executor.Current()->version == baseline.version && pending.Read(lease)->consent.id == ready.consent.id, "stale helper retargeted consent");
        } else {
          {
            sd::Handle mapped(CreateFileW(sd::ExtendedPath(files.Path(PendingPath(ready.consent.slot, L"ServerDeckSetup.exe"))).c_str(),
              GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
            Require(mapped.valid(), "mapped apply fixture");
            Require(sd::install::ApplySelectedPending(executor, pending, lease, ready.consent, candidate, policy, source, {}, report) && source.calls == 1 &&
              executor.Current()->consumedVersion == old.version.text && executor.Current()->consumedSetupHash == old.setupHash && !pending.Read(lease),
              "successful apply lost durable consumption or repeated freshness");
            Require(stages == std::vector<sd::install::MaintenanceStage>{sd::install::MaintenanceStage::recovering,
              sd::install::MaintenanceStage::revalidating, sd::install::MaintenanceStage::applying, sd::install::MaintenanceStage::recovering} &&
              std::wstring(sd::install::MaintenanceText(sd::install::MaintenanceStage::applying)) == L"Применяем обновление ServerDeck…",
              "helper status omitted applying or used wrong data");
          }
          PendingStore rotated(paths, Policy{}, validator);
          Require(!rotated.PrepareStartup(lease, *executor.Current()), "consumed cleanup required retired signing root");
          Require(sd::install::PrepareGuiStartup(executor, rotated, lease, paths, baseline.version, invocation, process) == sd::install::StartupAction::relaunch &&
            sd::install::PrepareGuiStartup(executor, rotated, lease, paths, old.version, invocation, process) == sd::install::StartupAction::host && !process.calls,
            "recovery used old mapped payload or reapplied consumed target");
        }
      }
      std::ifstream data(paths.data / L"startup-data-sentinel", std::ios::binary);
      Require(std::string((std::istreambuf_iterator<char>(data)), std::istreambuf_iterator<char>()) == "unchanged user data", "startup/apply changed user data");
    }
    std::filesystem::remove_all(root); root.clear(); std::cout << "pending update synthetic unit checks passed\n"; return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n'; if (!root.empty()) std::filesystem::remove_all(root); return 1;
  }
}
