#include "update_service.h"
#include "artifact_transfer.h"
#include "github_releases.h"
#include "mcp_json.h"
#include "security.h"
#include <algorithm>
#include <chrono>
#include <limits>
#include <winhttp.h>

namespace sd::updates {
namespace {
uint64_t Now() {
  return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
    std::chrono::system_clock::now().time_since_epoch()).count());
}
void Timestamp(const std::optional<uint64_t>& value) {
  if (value && *value > static_cast<uint64_t>(std::numeric_limits<int64_t>::max()) - 86400) throw Failure("RECOVERY_REQUIRED");
}
void Put(mcp::Json::Object& object, const char* key, const std::optional<uint64_t>& value) {
  Timestamp(value); if (value) object.emplace(key, static_cast<int64_t>(*value));
}
std::string SafeCode(const std::exception& error, const char* fallback = "NETWORK_UNAVAILABLE") {
  const std::string value(error.what());
  if (value.rfind("STORAGE_IO:", 0) == 0) return "STORAGE_IO";
  for (const auto* code : {"UPDATE_NOT_CONFIGURED", "NETWORK_UNAVAILABLE", "TIMEOUT", "CANCELLED", "SOURCE_UNTRUSTED",
      "SOURCE_EXPIRED", "SOURCE_CHANGED", "RELEASE_REVOKED", "RELEASE_INCOMPATIBLE", "INVALID_CATALOG",
      "INVALID_ARTIFACT", "DISK_SPACE", "OWNER_RUNNING", "BUSY", "STORAGE_IO", "RECOVERY_REQUIRED", "UNINSTALL_PARTIAL"})
    if (value == code) return value;
  return fallback;
}
[[noreturn]] void NetworkFailure(DWORD error) {
  if (error == ERROR_WINHTTP_TIMEOUT) throw Failure("TIMEOUT");
  if (error == ERROR_WINHTTP_SECURE_FAILURE || error == ERROR_WINHTTP_CLIENT_AUTH_CERT_NEEDED) throw Failure("SOURCE_UNTRUSTED");
  throw Failure("NETWORK_UNAVAILABLE");
}
class FilePreferenceStore final : public PreferenceStore {
 public:
  explicit FilePreferenceStore(const install::Paths& paths) : files_(paths) {}
  Preferences Load() override {
    return files_.Exists(L"data/update-preferences.v1") ? DecodePreferences(files_.ReadRecord(L"data/update-preferences.v1")) : Preferences{};
  }
  void Save(const Preferences& value) override { files_.WriteRecord(L"data/update-preferences.v1", EncodePreferences(value)); }
 private:
  install::Files files_;
};
struct Internet {
  HINTERNET value = nullptr;
  ~Internet() { if (value) WinHttpCloseHandle(value); }
};
struct Completion {
  sd::Handle event{CreateEventW(nullptr, FALSE, FALSE, nullptr)};
  sd::Handle closed{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
  std::mutex mutex;
  DWORD status = 0, error = 0, count = 0;
  static void CALLBACK Notify(HINTERNET, DWORD_PTR context, DWORD status, void* info, DWORD length) {
    auto* self = reinterpret_cast<Completion*>(context); if (!self) return;
    if (status == WINHTTP_CALLBACK_STATUS_HANDLE_CLOSING) { SetEvent(self->closed.get()); return; }
    if (status != WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE && status != WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE &&
        status != WINHTTP_CALLBACK_STATUS_READ_COMPLETE && status != WINHTTP_CALLBACK_STATUS_REQUEST_ERROR) return;
    {
      std::lock_guard<std::mutex> lock(self->mutex);
      self->status = status; self->count = length;
      if (status == WINHTTP_CALLBACK_STATUS_REQUEST_ERROR && info && length == sizeof(WINHTTP_ASYNC_RESULT))
        self->error = static_cast<WINHTTP_ASYNC_RESULT*>(info)->dwError;
    }
    SetEvent(self->event.get());
  }
  DWORD Await(DWORD expected, ULONGLONG deadline, const std::atomic<bool>& cancelled) {
    for (;;) {
      if (cancelled.load()) throw Failure("CANCELLED");
      if (GetTickCount64() >= deadline) throw Failure("TIMEOUT");
      const auto result = WaitForSingleObject(event.get(), 25);
      if (result == WAIT_TIMEOUT) continue;
      if (result != WAIT_OBJECT_0) throw Failure("NETWORK_UNAVAILABLE");
      std::lock_guard<std::mutex> lock(mutex);
      if (status == WINHTTP_CALLBACK_STATUS_REQUEST_ERROR) {
        NetworkFailure(error);
      }
      if (status != expected) throw Failure("NETWORK_UNAVAILABLE");
      return count;
    }
  }
};
class AsyncRequest {
 public:
  AsyncRequest(HINTERNET connection, const std::wstring& path) {
    if (!completion_.event.valid() || !completion_.closed.valid()) throw Failure("NETWORK_UNAVAILABLE");
    request_ = WinHttpOpenRequest(connection, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    if (!request_) throw Failure("NETWORK_UNAVAILABLE");
    DWORD_PTR context = reinterpret_cast<DWORD_PTR>(&completion_);
    if (!WinHttpSetOption(request_, WINHTTP_OPTION_CONTEXT_VALUE, &context, sizeof(context)) ||
        WinHttpSetStatusCallback(request_, Completion::Notify, WINHTTP_CALLBACK_FLAG_ALL_COMPLETIONS |
          WINHTTP_CALLBACK_FLAG_HANDLES, 0) == WINHTTP_INVALID_STATUS_CALLBACK) {
      WinHttpCloseHandle(request_); request_ = nullptr; throw Failure("NETWORK_UNAVAILABLE");
    }
    bound_ = true;
    DWORD disable = WINHTTP_DISABLE_REDIRECTS | WINHTTP_DISABLE_COOKIES | WINHTTP_DISABLE_AUTHENTICATION;
    DWORD logon = WINHTTP_AUTOLOGON_SECURITY_LEVEL_HIGH;
    if (!WinHttpSetOption(request_, WINHTTP_OPTION_DISABLE_FEATURE, &disable, sizeof(disable)) ||
        !WinHttpSetOption(request_, WINHTTP_OPTION_AUTOLOGON_POLICY, &logon, sizeof(logon))) {
      Close(); throw Failure("NETWORK_UNAVAILABLE");
    }
  }
  ~AsyncRequest() { Close(); }
  void Start(ULONGLONG deadline, const std::atomic<bool>& cancel, const std::wstring& headers = {}) {
    if (cancel.load()) throw Failure("CANCELLED");
    if (GetTickCount64() >= deadline) throw Failure("TIMEOUT");
    const BOOL result = WinHttpSendRequest(request_, headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str(),
      static_cast<DWORD>(headers.size()), WINHTTP_NO_REQUEST_DATA,
      0, 0, reinterpret_cast<DWORD_PTR>(&completion_));
    Pending(result); completion_.Await(WINHTTP_CALLBACK_STATUS_SENDREQUEST_COMPLETE, deadline, cancel);
    Pending(WinHttpReceiveResponse(request_, nullptr));
    completion_.Await(WINHTTP_CALLBACK_STATUS_HEADERS_AVAILABLE, deadline, cancel);
  }
  DWORD Read(uint8_t* bytes, DWORD maximum, ULONGLONG deadline, const std::atomic<bool>& cancel) {
    if (cancel.load()) throw Failure("CANCELLED");
    if (GetTickCount64() >= deadline) throw Failure("TIMEOUT");
    Pending(WinHttpReadData(request_, bytes, maximum, nullptr));
    return completion_.Await(WINHTTP_CALLBACK_STATUS_READ_COMPLETE, deadline, cancel);
  }
  HINTERNET get() const { return request_; }
 private:
  static void Pending(BOOL result) { if (!result) { const auto error = GetLastError(); if (error != ERROR_IO_PENDING) NetworkFailure(error); } }
  void Close() {
    if (!request_) return;
    const auto handle = request_; request_ = nullptr;
    WinHttpCloseHandle(handle);
    // Context and read buffers outlive the final callback; never abandon them
    // just because request cancellation raced with successful completion.
    if (bound_) WaitForSingleObject(completion_.closed.get(), INFINITE);
  }
  Completion completion_;
  HINTERNET request_ = nullptr;
  bool bound_ = false;
};
std::optional<std::wstring> Header(HINTERNET request, DWORD query) {
  std::array<wchar_t, 2049> text{}; DWORD size = static_cast<DWORD>(sizeof(text));
  if (!WinHttpQueryHeaders(request, query, WINHTTP_HEADER_NAME_BY_INDEX, text.data(), &size, WINHTTP_NO_HEADER_INDEX)) {
    if (GetLastError() == ERROR_WINHTTP_HEADER_NOT_FOUND) return {};
    throw Failure("INVALID_ARTIFACT");
  }
  if (size % sizeof(wchar_t) || size >= sizeof(text)) throw Failure("INVALID_ARTIFACT");
  return std::wstring(text.data());
}
class WinHttpMetadataTransport final : public MetadataTransport {
 public:
  explicit WinHttpMetadataTransport(const Version& current) : agent_(sd::Wide("ServerDeck/" + current.text + " (windows-x64)")) {}
  MetadataResponse Get(const MetadataRequest& input, const std::atomic<bool>& cancelled) override {
    if (cancelled.load()) throw Failure("CANCELLED");
    if (GetTickCount64() >= input.deadline) throw Failure("TIMEOUT");
    if (!input.limit || input.limit > 512 * 1024) throw Failure("INVALID_CATALOG");
    HttpsHost(input.url);
    const auto url = sd::Wide(input.url);
    URL_COMPONENTS parts{}; parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = std::numeric_limits<DWORD>::max();
    if (!WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &parts)) throw Failure("SOURCE_UNTRUSTED");
    Internet session{WinHttpOpen(agent_.c_str(), WINHTTP_ACCESS_TYPE_NO_PROXY,
      WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, WINHTTP_FLAG_ASYNC)};
    if (!session.value || !WinHttpSetTimeouts(session.value, 30000, 30000, 30000, 30000)) throw Failure("NETWORK_UNAVAILABLE");
    const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
    Internet connection{WinHttpConnect(session.value, host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0)};
    if (!connection.value) throw Failure("NETWORK_UNAVAILABLE");
    std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength); if (path.empty()) path = L"/";
    if (parts.dwExtraInfoLength) path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
    // Buffer must outlive AsyncRequest, which drains the closing callback.
    std::array<uint8_t, 65536> chunk{};
    AsyncRequest request(connection.value, path); request.Start(input.deadline, cancelled, sd::Wide(input.headers));
    MetadataResponse result; DWORD status = 0, length = sizeof(status);
    if (!WinHttpQueryHeaders(request.get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX, &status, &length, WINHTTP_NO_HEADER_INDEX)) throw Failure("NETWORK_UNAVAILABLE");
    result.status = status;
    if (status != 200) {
      if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
        const auto location = Header(request.get(), WINHTTP_QUERY_LOCATION);
        if (location) result.location = sd::Utf8(*location);
      }
      return result;
    }
    const auto size = Header(request.get(), WINHTTP_QUERY_CONTENT_LENGTH);
    std::optional<uint64_t> expected;
    if (size) {
      const auto text = sd::Utf8(*size); uint64_t count = 0;
      const auto parsed = std::from_chars(text.data(), text.data() + text.size(), count);
      if (parsed.ec != std::errc() || parsed.ptr != text.data() + text.size() || count > input.limit)
        throw Failure("INVALID_CATALOG");
      expected = count;
    }
    for (;;) {
      const auto count = request.Read(chunk.data(), static_cast<DWORD>(chunk.size()), input.deadline, cancelled);
      if (!count) break;
      if (count > input.limit - result.body.size()) throw Failure("INVALID_CATALOG");
      result.body.append(reinterpret_cast<const char*>(chunk.data()), count);
    }
    if (expected && *expected != result.body.size()) throw Failure("INVALID_CATALOG");
    return result;
  }
 private:
  std::wstring agent_;
};
class WinHttpArtifactRequest final : public ArtifactRequest {
 public:
  WinHttpArtifactRequest(const std::string& url, const std::wstring& agent) {
    const auto address = sd::Wide(url);
    URL_COMPONENTS parts{}; parts.dwStructSize = sizeof(parts);
    parts.dwHostNameLength = parts.dwUrlPathLength = parts.dwExtraInfoLength = std::numeric_limits<DWORD>::max();
    if (!WinHttpCrackUrl(address.c_str(), static_cast<DWORD>(address.size()), 0, &parts)) throw Failure("SOURCE_UNTRUSTED");
    session_.value = WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_NO_PROXY, WINHTTP_NO_PROXY_NAME, WINHTTP_NO_PROXY_BYPASS, WINHTTP_FLAG_ASYNC);
    if (!session_.value || !WinHttpSetTimeouts(session_.value, 30000, 30000, 30000, 60000)) throw Failure("NETWORK_UNAVAILABLE");
    const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
    connection_.value = WinHttpConnect(session_.value, host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!connection_.value) throw Failure("NETWORK_UNAVAILABLE");
    std::wstring path(parts.lpszUrlPath, parts.dwUrlPathLength); if (path.empty()) path = L"/";
    if (parts.dwExtraInfoLength) path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
    request_ = std::make_unique<AsyncRequest>(connection_.value, path);
  }
  ArtifactHeaders Start(uint64_t deadline, const std::atomic<bool>& cancel) override {
    request_->Start(deadline, cancel);
    ArtifactHeaders result; DWORD status = 0, size = sizeof(status);
    if (!WinHttpQueryHeaders(request_->get(), WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX)) throw Failure("NETWORK_UNAVAILABLE");
    result.status = status;
    if (status == 200) {
      if (const auto length = Header(request_->get(), WINHTTP_QUERY_CONTENT_LENGTH)) {
        if (length->empty() || length->size() > 20 || length->find_first_not_of(L"0123456789") != std::wstring::npos)
          throw Failure("INVALID_ARTIFACT");
        try { result.length = std::stoull(*length); } catch (...) { throw Failure("INVALID_ARTIFACT"); }
      }
    } else if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
      if (const auto location = Header(request_->get(), WINHTTP_QUERY_LOCATION)) result.location = sd::Utf8(*location);
    }
    return result;
  }
  size_t Read(uint8_t* bytes, size_t maximum, uint64_t deadline, const std::atomic<bool>& cancel) override {
    if (maximum > 65536) throw Failure("INVALID_ARTIFACT");
    return request_->Read(bytes, static_cast<DWORD>(maximum), deadline, cancel);
  }
 private:
  Internet session_, connection_;
  std::unique_ptr<AsyncRequest> request_;
};
class WinHttpArtifactTransport final : public ArtifactTransport {
 public:
  WinHttpArtifactTransport(Policy policy, const Version& current) : policy_(std::move(policy)) {
    if (!(ParseVersion(current.text) == current)) throw Failure("INVALID_ARTIFACT");
    agent_ = sd::Wide("ServerDeck/" + current.text + " (windows-x64)");
  }
  std::unique_ptr<ArtifactRequest> Open(const std::string& url) override {
    RequireDownloadUrl(policy_, url);
    return std::make_unique<WinHttpArtifactRequest>(url, agent_);
  }
 private:
  Policy policy_;
  std::wstring agent_;
};
}

std::string EncodePreferences(const Preferences& value) {
  mcp::Json::Object fields{{"enabled", value.enabled}};
  Put(fields, "lastAttempt", value.lastAttempt); Put(fields, "lastSuccess", value.lastSuccess); Put(fields, "deferredUntil", value.deferredUntil);
  return "SDUPREF001\n" + mcp::Encode(mcp::Json(fields)) + '\n';
}
Preferences DecodePreferences(const std::string& bytes) {
  try {
    constexpr size_t prefix = 11;
    if (bytes.size() > 8192 || bytes.size() <= prefix || bytes.compare(0, prefix, "SDUPREF001\n") || bytes.back() != '\n' ||
        bytes.find('\0') != std::string::npos || bytes.find('\r') != std::string::npos) throw Failure("RECOVERY_REQUIRED");
    const auto parsed = mcp::Decode(bytes.substr(prefix)); const auto& fields = parsed.object();
    Preferences value; value.enabled = std::get<bool>(fields.at("enabled").value);
    for (const auto& [key, item] : fields) {
      if (key == "enabled") continue;
      const auto count = item.integer(); if (count < 0) throw Failure("RECOVERY_REQUIRED");
      if (key == "lastAttempt") value.lastAttempt = static_cast<uint64_t>(count);
      else if (key == "lastSuccess") value.lastSuccess = static_cast<uint64_t>(count);
      else if (key == "deferredUntil") value.deferredUntil = static_cast<uint64_t>(count);
      else throw Failure("RECOVERY_REQUIRED");
    }
    EncodePreferences(value); return value;
  } catch (...) { throw Failure("RECOVERY_REQUIRED"); }
}
std::unique_ptr<CatalogSource> MakeWinHttpCatalogSource(const Policy& policy, const Version& current) {
  return std::make_unique<GitHubReleaseSource>(policy, current, MakeWinHttpMetadataTransport(current));
}
std::unique_ptr<MetadataTransport> MakeWinHttpMetadataTransport(const Version& current) {
  return std::make_unique<WinHttpMetadataTransport>(current);
}
std::unique_ptr<ArtifactTransport> MakeWinHttpArtifactTransport(const Policy& policy, const Version& current) {
  return std::make_unique<WinHttpArtifactTransport>(policy, current);
}
std::unique_ptr<PreferenceStore> MakeFilePreferenceStore(const install::Paths& paths) { return std::make_unique<FilePreferenceStore>(paths); }
UpdateService::UpdateService(std::optional<Policy> policy, Version current, PreferenceStore& store,
    CatalogSource* source, Clock clock, PendingPersistence* pending, ArtifactTransport* artifacts,
    std::optional<install::Installation> installed) : policy_(std::move(policy)), store_(store), source_(source),
    clock_(clock ? std::move(clock) : Now), pending_(pending), artifacts_(artifacts), installed_(std::move(installed)) {
  if (!(ParseVersion(current.text) == current)) throw Failure("INVALID_ARTIFACT");
  snapshot_.current = std::move(current); snapshot_.preferences = store_.Load(); EncodePreferences(snapshot_.preferences);
  if (policy_ && !source_) { ownedSource_ = MakeWinHttpCatalogSource(*policy_, snapshot_.current); source_ = ownedSource_.get(); }
  if (installed_) {
    install::EncodeInstallation(*installed_);
    if (!(installed_->version == snapshot_.current) || installed_->sid != sd::Utf8(sd::UserSid())) throw Failure("INVALID_ARTIFACT");
  }
  if (!policy_) { snapshot_.state = "failed"; snapshot_.code = "UPDATE_NOT_CONFIGURED"; }
  else if (pending_) {
    if (!artifacts_) { ownedArtifacts_ = MakeWinHttpArtifactTransport(*policy_, snapshot_.current); artifacts_ = ownedArtifacts_.get(); }
    restored_ = false; busy_ = true; snapshot_.state = "checking";
    const auto generation = ++generation_; Launch([this, generation] { RestoreWorker(generation); });
  }
}
UpdateService::~UpdateService() { StopAdmission(); Cancel(); Drain(); }
Snapshot UpdateService::Read() const { std::lock_guard<std::mutex> lock(mutex_); return snapshot_; }
bool UpdateService::Check() {
  std::lock_guard<std::mutex> command(command_);
  uint64_t generation;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopped_) throw Failure("CANCELLED");
    if (busy_) throw Failure("BUSY");
    auto preferences = snapshot_.preferences; preferences.lastAttempt = clock_();
    store_.Save(preferences); snapshot_.preferences = preferences;
    snapshot_.code.clear(); snapshot_.offer.reset(); snapshot_.bytes = 0; snapshot_.total.reset();
    if (!policy_) { snapshot_.state = "failed"; snapshot_.code = "UPDATE_NOT_CONFIGURED"; return false; }
    snapshot_.state = "checking"; busy_ = true; committed_ = false; cancelled_.store(false); generation = ++generation_;
  }
  Launch([this, generation] { Run(generation); }); return true;
}
void UpdateService::Launch(std::function<void()> work) {
  if (worker_.joinable()) worker_.join();
  try { worker_ = std::thread(std::move(work)); }
  catch (...) { std::lock_guard<std::mutex> lock(mutex_); busy_ = false; snapshot_.state = "failed"; snapshot_.code = "STORAGE_IO"; throw Failure("STORAGE_IO"); }
}
void UpdateService::ProjectPrepared() {
  snapshot_.preparedVersion = prepared_ ? prepared_->release.version.text : "";
  if (!prepared_) snapshot_.preparedCode.clear();
}
void UpdateService::LoadPrepared(uint64_t generation) {
  if (!pending_ || restored_) return;
  std::optional<PendingUpdate> restored;
  try { restored = pending_->Restore(); }
  catch (const std::exception& error) { throw Failure(SafeCode(error, "STORAGE_IO").c_str()); }
  if (restored && !Compatible(restored->release, *policy_)) throw Failure("RELEASE_INCOMPATIBLE");
  std::lock_guard<std::mutex> lock(mutex_);
  if (stopped_ || cancelled_.load() || generation != generation_) throw Failure("CANCELLED");
  // Bootstrap handles durable consumed/superseded cleanup before host. A stale
  // target must still never become an eligible ready offer in the live service.
  prepared_ = restored && snapshot_.current < restored->release.version ? std::move(restored) : std::nullopt;
  restored_ = true; snapshot_.preparedCode.clear(); ProjectPrepared();
  startupNotice_ = pending_->Notice();
  if (!startupNotice_.code.empty()) {
    const Failure notice(startupNotice_.code.c_str()); startupNotice_.code = SafeCode(notice, "STORAGE_IO");
    if (prepared_ && startupNotice_.version == prepared_->release.version.text) snapshot_.preparedCode = startupNotice_.code;
  }
}
void UpdateService::RestoreWorker(uint64_t generation) {
  try {
    LoadPrepared(generation);
    Finish(generation, [&](Snapshot& snapshot) {
      snapshot.state = !startupNotice_.code.empty() ? "failed" : prepared_ ? "ready" : "idle"; snapshot.code = startupNotice_.code;
      if (prepared_) snapshot.offer = prepared_->release;
    });
  } catch (const std::exception& error) {
    const auto code = SafeCode(error, "STORAGE_IO");
    Finish(generation, [&](Snapshot& snapshot) { snapshot.state = "failed"; snapshot.code = code; });
  }
}
void UpdateService::Finish(uint64_t generation, const std::function<void(Snapshot&)>& change) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (generation != generation_ || stopped_ || cancelled_.load()) { busy_ = false; return; }
  change(snapshot_); busy_ = false;
}
void UpdateService::Run(uint64_t generation) {
  try {
    LoadPrepared(generation);
    const auto bytes = source_->Fetch(cancelled_);
    if (cancelled_.load()) throw Failure("CANCELLED");
    const auto now = clock_(); const auto catalog = ParseCatalog(bytes, *policy_, now);
    const auto sameFiles = [](const Release& a, uint64_t appSize, const std::string& appHash, uint64_t setupSize, const std::string& setupHash) {
      return a.appSize == appSize && a.appHash == appHash && a.setupSize == setupSize && a.setupHash == setupHash;
    };
    for (const auto& release : catalog.releases) {
      if (installed_ && release.version == installed_->version && !sameFiles(release, installed_->app.size, installed_->app.hash, installed_->setup.size, installed_->setup.hash))
        throw Failure("SOURCE_CHANGED");
      if (catalog_) for (const auto& known : catalog_->releases) if (release.version == known.version &&
          !sameFiles(release, known.appSize, known.appHash, known.setupSize, known.setupHash)) throw Failure("SOURCE_CHANGED");
    }
    std::string preparedCode;
    if (prepared_) try { FindConsented(catalog, prepared_->release, *policy_); }
      catch (const Failure& error) { preparedCode = SafeCode(error); }
    const auto* offered = LatestCompatible(catalog, *policy_, snapshot_.current);
    const bool incompatible = !offered && std::any_of(catalog.releases.begin(), catalog.releases.end(), [&](const Release& release) {
      return snapshot_.current < release.version && !Compatible(release, *policy_);
    });
    const bool preparedFailure = prepared_ && !preparedCode.empty() && (!offered || offered->version == prepared_->release.version);
    Finish(generation, [&](Snapshot& snapshot) {
      if (!incompatible && !preparedFailure) {
        auto preferences = snapshot.preferences; preferences.lastSuccess = now; store_.Save(preferences);
        snapshot.preferences = preferences;
      }
      snapshot.state = offered ? "available" : incompatible ? "failed" : "current";
      snapshot.code = incompatible ? "RELEASE_INCOMPATIBLE" : "";
      if (offered) snapshot.offer = *offered;
      catalog_ = catalog; snapshot.preparedCode = preparedCode;
      if (prepared_ && offered && offered->version == prepared_->release.version) {
        snapshot.state = preparedCode.empty() ? "ready" : "failed";
        snapshot.code = preparedCode; snapshot.offer = preparedCode.empty() ? std::optional<Release>{prepared_->release} : std::nullopt;
      } else if (prepared_ && !offered && !preparedCode.empty()) {
        snapshot.state = "failed"; snapshot.code = preparedCode;
      }
    });
  } catch (const std::exception& error) {
    const auto code = SafeCode(error);
    Finish(generation, [&](Snapshot& snapshot) {
      snapshot.state = "failed"; snapshot.code = code; snapshot.offer.reset();
      if (prepared_) snapshot.preparedCode = code;
    });
  }
}
bool UpdateService::Download(const std::string& version) {
  const auto requested = ParseVersion(version);
  std::lock_guard<std::mutex> command(command_);
  Release release; std::string bytes; uint64_t generation;
  {
    std::lock_guard<std::mutex> lock(mutex_);
    if (stopped_) throw Failure("CANCELLED");
    if (busy_) throw Failure("BUSY");
    if (!policy_) throw Failure("UPDATE_NOT_CONFIGURED");
    if (!pending_ || !artifacts_) throw Failure("STORAGE_IO");
    if (!restored_ || !catalog_ || snapshot_.state != "available" || !snapshot_.offer || !(snapshot_.offer->version == requested)) throw Failure("SOURCE_CHANGED");
    release = *snapshot_.offer; bytes = catalog_->signedBytes;
    snapshot_.state = "downloading"; snapshot_.code.clear(); snapshot_.bytes = 0; snapshot_.total.reset();
    busy_ = true; committed_ = false; cancelled_.store(false); generation = ++generation_;
  }
  Launch([this, generation, release, bytes] { DownloadWorker(generation, release, bytes); }); return true;
}
void UpdateService::DownloadWorker(uint64_t generation, Release release, std::string catalog) {
  try {
    const auto consentAt = clock_();
    const auto verified = ParseCatalog(catalog, *policy_, consentAt);
    FindConsented(verified, release, *policy_);
    const auto ready = pending_->Download(release, catalog, consentAt, *artifacts_, cancelled_, [&](const PendingWrite& write) {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopped_ || cancelled_.load() || generation != generation_) throw Failure("CANCELLED");
      write([&] {
        committed_ = true; snapshot_.state = "ready"; snapshot_.code.clear(); snapshot_.offer = release;
        snapshot_.bytes = release.setupSize; snapshot_.preparedVersion = release.version.text; snapshot_.preparedCode.clear();
      });
    }, [&](uint64_t count, std::optional<uint64_t> total) {
      std::lock_guard<std::mutex> lock(mutex_);
      if (stopped_ || cancelled_.load() || generation != generation_) throw Failure("CANCELLED");
      if (count > release.setupSize || (total && *total != release.setupSize)) throw Failure("INVALID_ARTIFACT");
      snapshot_.bytes = count; snapshot_.total = total; snapshot_.state = count == release.setupSize ? "verifying" : "downloading";
    });
    Finish(generation, [&](Snapshot&) { prepared_ = ready; restored_ = true; ProjectPrepared(); });
  } catch (const std::exception& error) {
    const auto code = SafeCode(error, "STORAGE_IO");
    Finish(generation, [&](Snapshot& snapshot) {
      if (committed_) { restored_ = false; prepared_.reset(); snapshot.preparedCode = code; }
      snapshot.state = "failed"; snapshot.code = code;
      // Keep a trusted offer available for presentation, never as a ready state.
    });
  }
}
void UpdateService::Cancel() {
  std::lock_guard<std::mutex> command(command_);
  std::lock_guard<std::mutex> lock(mutex_);
  if (busy_ && !committed_) { cancelled_.store(true); ++generation_; snapshot_.state = "failed"; snapshot_.code = "CANCELLED"; snapshot_.offer.reset(); }
}
void UpdateService::SetEnabled(bool enabled) {
  std::lock_guard<std::mutex> command(command_);
  std::lock_guard<std::mutex> lock(mutex_);
  if (stopped_) throw Failure("CANCELLED");
  auto preferences = snapshot_.preferences; preferences.enabled = enabled;
  store_.Save(preferences); snapshot_.preferences = preferences;
}
void UpdateService::Defer() {
  std::lock_guard<std::mutex> command(command_);
  std::lock_guard<std::mutex> lock(mutex_);
  if (stopped_) throw Failure("CANCELLED");
  if (busy_) throw Failure("BUSY");
  const auto now = clock_(); Timestamp(now);
  auto preferences = snapshot_.preferences;
  const auto scheduled = preferences.lastAttempt ? *preferences.lastAttempt + 86400 : 0;
  preferences.deferredUntil = scheduled > now ? scheduled : now + 86400;
  store_.Save(preferences); snapshot_.preferences = preferences;
  snapshot_.state = "idle"; snapshot_.code.clear(); snapshot_.offer.reset();
}
void UpdateService::StopAdmission() { std::lock_guard<std::mutex> lock(mutex_); stopped_ = true; ++generation_; }
void UpdateService::Drain() { std::lock_guard<std::mutex> command(command_); if (worker_.joinable()) worker_.join(); }
bool UpdateService::TryDrain() {
  std::unique_lock<std::mutex> command(command_, std::try_to_lock); if (!command.owns_lock()) return false;
  if (worker_.joinable() && WaitForSingleObject(worker_.native_handle(), 0) != WAIT_OBJECT_0) return false;
  if (worker_.joinable()) worker_.join(); return true;
}
Release Revalidate(CatalogSource& source, const Policy& policy, const Release& consent, const std::atomic<bool>& cancelled, UpdateService::Clock clock) {
  const auto bytes = source.FetchFor(consent, cancelled); if (cancelled.load()) throw Failure("CANCELLED");
  const auto catalog = ParseCatalog(bytes, policy, clock ? clock() : Now());
  return *FindConsented(catalog, consent, policy);
}
}  // namespace sd::updates
