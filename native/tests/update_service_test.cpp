#include "update_service.h"
#include "security.h"
#include <bcrypt.h>
#include <condition_variable>
#include <iostream>

namespace {
void Require(bool condition, const char* message) { if (!condition) throw std::runtime_error(message); }
struct Signer {
  BCRYPT_ALG_HANDLE algorithm = nullptr;
  BCRYPT_KEY_HANDLE key = nullptr;
  Signer() {
    Require(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_ECDSA_P256_ALGORITHM, nullptr, 0) >= 0, "algorithm");
    Require(BCryptGenerateKeyPair(algorithm, &key, 256, 0) >= 0 && BCryptFinalizeKeyPair(key, 0) >= 0, "key");
  }
  ~Signer() { if (key) BCryptDestroyKey(key); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
  static std::string Hex(const uint8_t* bytes, size_t length) {
    std::string result; constexpr char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < length; ++i) { result += hex[bytes[i] >> 4]; result += hex[bytes[i] & 15]; }
    return result;
  }
  sd::updates::Policy Policy() {
    uint8_t blob[72]{}; ULONG length = 0;
    Require(BCryptExportKey(key, nullptr, BCRYPT_ECCPUBLIC_BLOB, blob, sizeof(blob), &length, 0) >= 0 && length == 72, "export");
    return sd::updates::ParsePolicy("{\"schema\":1,\"endpoint\":\"https://updates.example/stable\",\"downloadHosts\":[\"assets.example\"],"
      "\"storeFormat\":2,\"keys\":[{\"id\":\"unit\",\"p256\":\"" + Hex(blob + 8, 64) + "\"}]}");
  }
  std::string Catalog(const std::string& records, int count = 1) {
    const std::string bytes = "SDRELEASES001\n99990\n100100\n" + std::to_string(count) + '\n' + records;
    const auto hash = sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
    uint8_t digest[32]{}; for (size_t i = 0; i < 32; ++i) digest[i] = static_cast<uint8_t>(std::stoul(hash.substr(i * 2, 2), nullptr, 16));
    uint8_t signature[64]{}; ULONG length = 0;
    Require(BCryptSignHash(key, nullptr, digest, 32, signature, 64, &length, 0) >= 0 && length == 64, "sign");
    return "SDCATALOG001\nunit\n" + Hex(signature, 64) + '\n' + bytes;
  }
};
std::string Record(const char* version = "0.2.0", const char* abi = "1") {
  return std::string(version) + "\nwindows-x64\n" + abi + "\n2\n99900\n12\n" + std::string(64, 'a') +
    "\n10\n" + std::string(64, 'b') + "\nhttps://assets.example/setup.exe\n0KLQtdGB0YI=\n";
}
struct Store : sd::updates::PreferenceStore {
  sd::updates::Preferences value;
  bool fail = false;
  sd::updates::Preferences Load() override { return value; }
  void Save(const sd::updates::Preferences& next) override { if (fail) throw sd::updates::Failure("STORAGE_IO"); value = next; }
};
struct Source : sd::updates::CatalogSource {
  std::string bytes, failure, validatedVersion;
  bool block = false, ignoreCancel = false, entered = false, released = false;
  int requests = 0;
  std::function<void()> beforeReturn;
  std::string FetchFor(const sd::updates::Release& consent, const std::atomic<bool>& cancelled) override {
    validatedVersion = consent.version.text; return Fetch(cancelled);
  }
  std::mutex mutex;
  std::condition_variable changed;
  std::string Fetch(const std::atomic<bool>& cancelled) override {
    std::unique_lock<std::mutex> lock(mutex); ++requests; entered = true; changed.notify_all();
    if (block) changed.wait(lock, [&] { return released || (!ignoreCancel && cancelled.load()); });
    if (!failure.empty()) throw sd::updates::Failure(failure.c_str());
    if (beforeReturn) beforeReturn();
    return bytes;
  }
  void Entered() { std::unique_lock<std::mutex> lock(mutex); Require(changed.wait_for(lock, std::chrono::seconds(2), [&] { return entered; }), "source not entered"); }
  void Release() { std::lock_guard<std::mutex> lock(mutex); released = true; changed.notify_all(); }
};
sd::updates::PendingUpdate Pending(const sd::updates::Release& release, const std::string& catalog, uint64_t at = 100000) {
  sd::updates::PendingConsent consent{sd::Utf8(sd::Uuid()), sd::Utf8(sd::UserSid()), 0, release.version,
    {release.appSize, release.appHash}, {release.setupSize, release.setupHash},
    sd::Sha256(reinterpret_cast<const uint8_t*>(catalog.data()), catalog.size()), at};
  return {consent, release, catalog};
}
struct Artifacts : sd::updates::ArtifactTransport {
  std::unique_ptr<sd::updates::ArtifactRequest> Open(const std::string&) override { throw std::runtime_error("unexpected real transfer in service unit"); }
};
struct Backend : sd::updates::PendingPersistence {
  sd::updates::PendingNotice notice;
  sd::updates::PendingNotice Notice() const override { return notice; }
  std::optional<sd::updates::PendingUpdate> persisted;
  int downloads = 0, restores = 0;
  bool beforeCommit = false, afterCommit = false, blockRestore = false;
  bool ignoreCancel = false, failRestore = false;
  bool cleanupFailure = false;
  std::string downloadFailure;
  bool enteredDownload = false, enteredRestore = false, released = false;
  std::mutex mutex; std::condition_variable changed;
  std::optional<sd::updates::PendingUpdate> Restore() override {
    std::unique_lock<std::mutex> lock(mutex); ++restores; enteredRestore = true; changed.notify_all();
    if (blockRestore) changed.wait(lock, [&] { return released; });
    if (failRestore) throw std::runtime_error("synthetic local access failure");
    return persisted;
  }
  sd::updates::PendingUpdate Download(const sd::updates::Release& release, const std::string& catalog, uint64_t at,
      sd::updates::ArtifactTransport&, const std::atomic<bool>& cancel, const sd::updates::PendingCommit& commit,
      sd::updates::ArtifactProgress progress) override {
    std::unique_lock<std::mutex> lock(mutex); ++downloads;
    if (!downloadFailure.empty()) throw sd::updates::Failure(downloadFailure.c_str());
    auto candidate = Pending(release, catalog, at); candidate.consent.slot = persisted ? 1 - persisted->consent.slot : 0;
    progress(0, {}); progress(release.setupSize, {});
    enteredDownload = true; changed.notify_all();
    if (beforeCommit) changed.wait(lock, [&] { return released; });
    if (cancel.load() && !ignoreCancel) throw sd::updates::Failure("CANCELLED");
    bool published = false;
    try {
      commit([&](const std::function<void()>& onPublished) {
        persisted = candidate; onPublished(); published = true;
        if (cleanupFailure) throw sd::updates::Failure("STORAGE_IO");
      });
    } catch (const sd::updates::Failure&) { if (!published) throw; }
    if (afterCommit) changed.wait(lock, [&] { return released; });
    return candidate;
  }
  void Entered(bool restore = false) {
    std::unique_lock<std::mutex> lock(mutex);
    Require(changed.wait_for(lock, std::chrono::seconds(2), [&] { return restore ? enteredRestore : enteredDownload; }), "backend not entered");
  }
  void Release() { std::lock_guard<std::mutex> lock(mutex); released = true; changed.notify_all(); }
};
template<class F> void Reject(F action, const char* code) {
  try { action(); } catch (const sd::updates::Failure& error) { Require(std::string(error.what()) == code, "wrong code"); return; }
  throw std::runtime_error("operation accepted");
}
}
int main() {
  using namespace sd::updates;
  try {
    Store store;
    Signer signer; const auto policy = signer.Policy();
    const auto current = ParseVersion("0.1.0");
    std::atomic<uint64_t> now{100000}; const auto clock = [&] { return now.load(); };
    auto pref = Preferences{false, 10, 20, 30}; const auto encoded = EncodePreferences(pref);
    Require(DecodePreferences(encoded).lastSuccess == 20 && !DecodePreferences(encoded).enabled, "preference roundtrip");
    for (const auto& invalid : {std::string(), encoded + "x", std::string("SDUPREF001\n{\"enabled\":true,\"other\":1}\n"),
        std::string("SDUPREF001\n{\"enabled\":true,\"lastAttempt\":-1}\n"), std::string("SDUPREF001\n{\"enabled\":false,\"enabled\":true}\n")})
      Reject([&] { DecodePreferences(invalid); }, "RECOVERY_REQUIRED");
    {
      wchar_t temp[32768]{}; Require(GetTempPathW(32768, temp) != 0, "temp");
      const auto root = std::filesystem::path(temp) / (L"ServerDeckUpdatePrefUnit-" + sd::Uuid());
      sd::SecureDirectory(root);
      try {
        const sd::install::Paths paths{root / L"install", root / L"data", root / L"programs", sd::UserSid()};
        auto persisted = MakeFilePreferenceStore(paths);
        Require(persisted->Load().enabled, "missing preference default");
        persisted->Save(pref);
        Require(std::filesystem::exists(paths.data / L"update-preferences.v1") &&
          !std::filesystem::exists(paths.install / L"data"), "preference wrong root");
        auto reopened = MakeFilePreferenceStore(paths);
        Require(!reopened->Load().enabled && reopened->Load().lastAttempt == 10, "preference persistence");
        sd::install::Files files(paths); files.WriteRecord(L"data/update-preferences.v1", "corrupt");
        Reject([&] { reopened->Load(); }, "RECOVERY_REQUIRED");
        Require(files.ReadRecord(L"data/update-preferences.v1") == "corrupt", "invalid preference silently reset");
      } catch (...) { std::filesystem::remove_all(root); throw; }
      std::filesystem::remove_all(root);
    }
    {
      Source source; UpdateService service({}, current, store, &source, clock);
      Require(!service.Check() && service.Read().code == "UPDATE_NOT_CONFIGURED" && source.requests == 0, "missing policy network");
    }
    {
      Source source; source.bytes = signer.Catalog(Record());
      UpdateService service(policy, current, store, &source, clock);
      service.SetEnabled(false); Require(service.Check(), "manual disabled refused"); service.Drain();
      auto result = service.Read();
      Require(result.state == "available" && result.offer && result.offer->version.text == "0.2.0", "offer");
      Require(!result.preferences.enabled && result.preferences.lastAttempt == now && result.preferences.lastSuccess == now, "manual changes enabled/timestamps");
      Require(result.offer->published == 99900 && result.offer->setupSize == 12 && result.offer->platform == "windows-x64" &&
        result.offer->bootstrapAbi == 1 && result.offer->storeFormat == 2 && !result.total && result.bytes == 0, "signed offer fields");
      service.Defer(); Require(service.Read().state == "idle" && service.Read().preferences.deferredUntil == 186400, "defer");
      // Manual checks bypass both lastAttempt and deferral without changing enabled.
      Require(service.Check(), "manual deferral refused"); service.Drain();
      source.bytes = signer.Catalog("", 0); Require(service.Check(), "empty request"); service.Drain();
      Require(service.Read().state == "current" && !service.Read().offer, "signed empty not current");
      ++now; source.bytes = signer.Catalog(Record("0.3.0", "2")); service.Check(); service.Drain();
      Require(service.Read().code == "RELEASE_INCOMPATIBLE" && !service.Read().offer &&
        service.Read().preferences.lastSuccess == 100000 && store.value.lastSuccess == 100000, "incompatible changed last success");
      source.bytes = "malformed response"; ++now; service.Check(); service.Drain();
      Require(service.Read().state == "failed" && service.Read().preferences.lastSuccess == 100000 && service.Read().preferences.lastAttempt == 100002, "failure overwrote success");
      store.fail = true; Reject([&] { service.SetEnabled(true); }, "STORAGE_IO");
      Require(!service.Read().preferences.enabled, "failed setting changed memory"); store.fail = false;
      service.StopAdmission(); Reject([&] { service.Check(); }, "CANCELLED");
    }
    {
      Source source; source.bytes = signer.Catalog(Record()); source.block = true; source.ignoreCancel = true;
      UpdateService service(policy, current, store, &source, clock); service.Check(); source.Entered();
      Reject([&] { service.Check(); }, "BUSY"); service.Cancel();
      Require(service.Read().code == "CANCELLED", "cancel snapshot");
      source.Release(); service.Drain();
      Require(service.Read().code == "CANCELLED" && !service.Read().offer, "late reply resurrected offer");
      source.block = false; service.Check(); service.Drain(); Require(service.Read().offer.has_value(), "post cancel retry");
    }
    {
      Source source; source.bytes = signer.Catalog(Record()); std::atomic<bool> cancelled{false};
      const auto consent = ParseCatalog(source.bytes, policy, now).releases.front();
      Require(Revalidate(source, policy, consent, cancelled, clock).version == consent.version && source.requests == 1 &&
        source.validatedVersion == consent.version.text, "fresh exact-target apply request missing");
      source.bytes = signer.Catalog("", 0); Reject([&] { Revalidate(source, policy, consent, cancelled, clock); }, "RELEASE_REVOKED");
      source.bytes = signer.Catalog(Record("0.3.0") + Record(), 2);
      Require(Revalidate(source, policy, consent, cancelled, clock).version == consent.version, "consent retargeted");
      source.beforeReturn = [&] { now = 100101; };
      Reject([&] { Revalidate(source, policy, consent, cancelled, clock); }, "SOURCE_EXPIRED");
      source.beforeReturn = {}; now = 100001;
      source.failure = "NETWORK_UNAVAILABLE"; Reject([&] { Revalidate(source, policy, consent, cancelled, clock); }, "NETWORK_UNAVAILABLE");
    }
    const auto oldCatalog = signer.Catalog(Record()), newCatalog = signer.Catalog(Record("0.3.0") + Record(), 2);
    const auto oldRelease = ParseCatalog(oldCatalog, policy, now).releases.front();
    {
      Backend backend; backend.persisted = Pending(oldRelease, oldCatalog); backend.notice = {oldRelease.version.text, "NETWORK_UNAVAILABLE"};
      Artifacts artifacts; Source source; source.bytes = oldCatalog;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      Require(service.Read().state == "failed" && service.Read().code == "NETWORK_UNAVAILABLE" &&
        service.Read().preparedVersion == oldRelease.version.text && service.Read().preparedCode == "NETWORK_UNAVAILABLE" && !source.requests,
        "fallback falsely restored ready or lost prepared identity");
      Require(!service.AcceptRestart(oldRelease.version.text), "startup failed prepared restart accepted");
      service.Check(); service.Drain(); Require(service.Read().state == "ready" && service.Read().preparedCode.empty(), "fresh check did not clear startup failure");
    }
    {
      Backend backend; backend.persisted = Pending(oldRelease, oldCatalog); backend.beforeCommit = true; backend.ignoreCancel = true;
      Artifacts artifacts; Source source; source.bytes = newCatalog;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      Require(service.Read().state == "ready" && source.requests == 0 && backend.downloads == 0, "restore started network/download");
      service.Check(); service.Drain();
      Require(service.Read().offer->version.text == "0.3.0" && service.Read().preparedVersion == oldRelease.version.text && backend.downloads == 0,
        "check lost prior ready or downloaded without consent");
      Reject([&] { service.Download("0.4.0"); }, "SOURCE_CHANGED");
      service.Download("0.3.0"); backend.Entered();
      Require(!service.AcceptRestart(oldRelease.version.text), "restart during active replacement");
      Require(service.Read().state == "verifying" && !service.Read().total && !service.TryDrain(), "progress/drain state");
      Reject([&] { service.Check(); }, "BUSY");
      service.Cancel(); backend.Release(); service.Drain();
      Require(service.Read().code == "CANCELLED" && backend.persisted->release.version == oldRelease.version &&
        service.Read().preparedVersion == oldRelease.version.text && backend.downloads == 1, "cancel consumed prior readiness");
      Require(!service.AcceptRestart("0.4.0"), "wrong restart target accepted");
      Require(service.AcceptRestart(oldRelease.version.text), "cancelled replacement blocked retained ready");
      Require(!service.AcceptRestart(oldRelease.version.text), "stopped service accepted again");
      Reject([&] { service.Check(); }, "CANCELLED");
    }
    {
      Backend backend; backend.persisted = Pending(oldRelease, oldCatalog); backend.downloadFailure = "NETWORK_UNAVAILABLE";
      Artifacts artifacts; Source source; source.bytes = newCatalog;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      service.Check(); service.Drain(); service.Download("0.3.0"); service.Drain();
      Require(service.Read().state == "failed" && service.Read().code == "NETWORK_UNAVAILABLE" &&
        service.Read().preparedCode.empty() && service.AcceptRestart(oldRelease.version.text), "failed replacement blocked retained ready");
    }
    for (const bool cleanupFailure : {false, true}) {
      Backend backend; backend.afterCommit = true; backend.cleanupFailure = cleanupFailure; Artifacts artifacts; Source source; source.bytes = oldCatalog;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      service.Check(); service.Drain(); service.Download(oldRelease.version.text); backend.Entered();
      // Wait for the commit callback to complete, not merely progress publication.
      { std::unique_lock<std::mutex> lock(backend.mutex); }
      Require(service.Read().state == "ready" && !service.TryDrain(), "committed ready not published atomically");
      service.Cancel(); Require(service.Read().state == "ready" && service.Read().code.empty(), "late cancel undid ready");
      backend.Release(); service.Drain(); Require(service.TryDrain(), "completed worker not drained");
    }
    {
      Backend backend; backend.cleanupFailure = true; Artifacts artifacts; Source source; source.bytes = oldCatalog;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      service.Check(); service.Drain(); service.Download(oldRelease.version.text); service.Drain();
      Require(service.Read().state == "ready" && service.Read().preparedVersion == oldRelease.version.text &&
        service.Read().code.empty() && backend.persisted.has_value(), "write-then-cleanup-failure left verifying");
    }
    {
      Backend backend; backend.persisted = Pending(oldRelease, oldCatalog); Artifacts artifacts;
      Source source; source.bytes = signer.Catalog(Record("0.3.0"));
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      service.Check(); service.Drain();
      Require(service.Read().state == "available" && service.Read().preparedCode == "RELEASE_REVOKED", "replacement hid revocation");
      Require(!service.AcceptRestart(oldRelease.version.text), "revoked prepared restart accepted");
      const auto success = service.Read().preferences.lastSuccess;
      ++now; source.bytes = signer.Catalog("", 0); service.Check(); service.Drain();
      Require(service.Read().state == "failed" && service.Read().code == "RELEASE_REVOKED" && service.Read().preferences.lastSuccess == success &&
        service.Read().preparedVersion == oldRelease.version.text, "revocation became current/success or lost pending");
      source.failure = "NETWORK_UNAVAILABLE"; service.Check(); service.Drain();
      Require(service.Read().preparedCode == "NETWORK_UNAVAILABLE" && backend.persisted.has_value(), "offline check deleted pending");
    }
    {
      Backend backend; backend.blockRestore = true; backend.persisted = Pending(oldRelease, oldCatalog); Artifacts artifacts; Source source;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); backend.Entered(true);
      Require(!service.TryDrain(), "live restore treated as drained"); service.Cancel(); backend.Release(); service.Drain();
      Require(service.Read().code == "CANCELLED" && service.Read().preparedVersion.empty(), "late restore resurrected readiness");
      Require(!service.AcceptRestart(oldRelease.version.text), "unrestored restart accepted");
    }
    {
      Backend backend; backend.failRestore = true; Artifacts artifacts; Source source; source.bytes = oldCatalog;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain();
      Require(service.Read().code == "STORAGE_IO" && source.requests == 0, "local restore mislabeled as network/current");
      backend.failRestore = false; service.Check(); service.Drain();
      Require(service.Read().state == "available", "restore failure not retryable");
    }
    {
      Backend backend; Artifacts artifacts; Source source; source.bytes = oldCatalog; now = 100000;
      UpdateService service(policy, current, store, &source, clock, &backend, &artifacts); service.Drain(); service.Check(); service.Drain();
      now = 100101; service.Download(oldRelease.version.text); service.Drain();
      Require(service.Read().code == "SOURCE_EXPIRED" && backend.downloads == 0, "expired consent reached persistence"); now = 100001;
    }
    {
      Source source; source.bytes = oldCatalog; UpdateService service(policy, current, store, &source, clock);
      service.Check(); service.Drain();
      auto changed = Record(); changed.replace(changed.find(std::string(64, 'a')), 64, std::string(64, 'c'));
      source.bytes = signer.Catalog(changed); service.Check(); service.Drain();
      Require(service.Read().code == "SOURCE_CHANGED", "same-version changed bytes accepted");
    }
    {
      Source source; auto changed = Record(current.text.c_str()); changed.replace(changed.find(std::string(64, 'a')), 64, std::string(64, 'c'));
      source.bytes = signer.Catalog(changed);
      sd::install::Installation baseline{sd::Utf8(sd::UserSid()), current, {10, std::string(64, 'b')}, {12, std::string(64, 'a')}, {}, {}};
      UpdateService service(policy, current, store, &source, clock, nullptr, nullptr, baseline); service.Check(); service.Drain();
      Require(service.Read().code == "SOURCE_CHANGED", "installed identity conflict became current");
    }
    std::cout << "update service synthetic unit checks passed\n"; return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
