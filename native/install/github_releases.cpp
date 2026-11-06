#include "github_releases.h"
#include "artifact_transfer.h"
#include "mcp_json.h"
#include "security.h"
#include <algorithm>
#include <chrono>
#include <set>

namespace sd::updates {
namespace {
constexpr size_t kApiLimit = 512 * 1024;
constexpr char kDownloadPrefix[] = "https://github.com/unng-lab/serverdeck/releases/download/";
constexpr char kTagPrefix[] = "https://api.github.com/repos/unng-lab/serverdeck/releases/tags/";
[[noreturn]] void Invalid() { throw Failure("INVALID_CATALOG"); }
bool Hex(const std::string& value) {
  return value.size() == 64 && value.find_first_not_of("0123456789abcdef") == std::string::npos;
}
std::string Tag(const Version& version) {
  return "v" + version.text;
}
int Nibble(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  Invalid();
}
std::string AssetUrl(const std::string& url, const Version& version, const std::string& name) {
  if (url.rfind(kDownloadPrefix, 0) || url.size() > 2048) Invalid();
  const auto tail = url.substr(sizeof(kDownloadPrefix) - 1);
  const auto slash = tail.find('/');
  if (slash == std::string::npos || tail.substr(slash + 1) != name) Invalid();
  const auto raw = tail.substr(0, slash); std::string decoded;
  for (size_t i = 0; i < raw.size(); ++i) {
    if (raw[i] != '%') decoded += raw[i];
    else {
      if (raw.size() - i < 3) Invalid();
      decoded += static_cast<char>((Nibble(raw[i + 1]) << 4) | Nibble(raw[i + 2])); i += 2;
    }
  }
  if (decoded != "v" + version.text) Invalid();
  return kDownloadPrefix + Tag(version) + "/" + name;
}
void Published(const std::string& value) {
  if (value.size() != 20 || value[4] != '-' || value[7] != '-' || value[10] != 'T' ||
      value[13] != ':' || value[16] != ':' || value[19] != 'Z') Invalid();
  const auto number = [&](size_t start, size_t count) {
    WORD n = 0;
    for (size_t i = start; i < start + count; ++i) {
      if (value[i] < '0' || value[i] > '9') Invalid();
      n = static_cast<WORD>(n * 10 + value[i] - '0');
    }
    return n;
  };
  SYSTEMTIME time{}; time.wYear = number(0, 4); time.wMonth = number(5, 2); time.wDay = number(8, 2);
  time.wHour = number(11, 2); time.wMinute = number(14, 2); time.wSecond = number(17, 2);
  FILETIME encoded{}; SYSTEMTIME decoded{};
  if (time.wYear < 1970 || !SystemTimeToFileTime(&time, &encoded) || !FileTimeToSystemTime(&encoded, &decoded) ||
      time.wYear != decoded.wYear || time.wMonth != decoded.wMonth || time.wDay != decoded.wDay ||
      time.wHour != decoded.wHour || time.wMinute != decoded.wMinute || time.wSecond != decoded.wSecond) Invalid();
}
struct Asset { uint64_t size = 0; std::string hash, url; };
struct ApiRelease { Version version; Asset setup, catalog; };
ApiRelease ParseApi(const std::string& body, bool target) {
  try {
    if (body.empty() || body.size() > kApiLimit) Invalid();
    const auto json = mcp::Decode(body);
    if (std::get<bool>(json.at("draft").value) || std::get<bool>(json.at("prerelease").value))
      throw Failure(target ? "RELEASE_REVOKED" : "INVALID_CATALOG");
    Published(json.at("published_at").string());
    const auto tag = json.at("tag_name").string();
    if (tag.empty() || tag[0] != 'v') Invalid();
    ApiRelease result; result.version = ParseVersion(tag.substr(1));
    const auto& assets = std::get<mcp::Json::Array>(json.at("assets").value);
    if (assets.size() > 128) Invalid();
    bool setup = false, catalog = false;
    for (const auto& item : assets) {
      const auto& name = item.at("name").string();
      const bool isSetup = name == "ServerDeckSetup.exe", isCatalog = name == "serverdeck-update-catalog.txt";
      if (!isSetup && (!isCatalog || target)) continue;
      bool& found = isSetup ? setup : catalog; if (found) Invalid(); found = true;
      if (item.at("state").string() != "uploaded") throw Failure(target ? "RELEASE_REVOKED" : "INVALID_CATALOG");
      const auto size = item.at("size").integer(); const auto& digest = item.at("digest").string();
      if (size <= 0 || static_cast<uint64_t>(size) > (isSetup ? kArtifactLimit : kCatalogLimit) ||
          digest.rfind("sha256:", 0) || !Hex(digest.substr(7))) Invalid();
      Asset& asset = isSetup ? result.setup : result.catalog;
      asset.size = static_cast<uint64_t>(size); asset.hash = digest.substr(7);
      asset.url = AssetUrl(item.at("browser_download_url").string(), result.version, name);
    }
    if (!setup) throw Failure(target ? "RELEASE_REVOKED" : "INVALID_CATALOG");
    if (!target && !catalog) Invalid();
    return result;
  } catch (const Failure&) { throw; }
  catch (...) { Invalid(); }
}
void CheckSetup(const Release& release, const ApiRelease& api) {
  if (!(release.version == api.version) || release.setupSize != api.setup.size ||
      release.setupHash != api.setup.hash || release.url != api.setup.url) throw Failure("SOURCE_CHANGED");
}
}
void ValidateGitHubPolicy(const Policy& policy) {
  const std::set<std::string> expected{"github.com", "release-assets.githubusercontent.com",
    "objects.githubusercontent.com", "github-releases.githubusercontent.com"};
  if (policy.endpoint != kGitHubLatest || policy.downloadHosts.size() != expected.size() ||
      std::set<std::string>(policy.downloadHosts.begin(), policy.downloadHosts.end()) != expected) Invalid();
}
GitHubReleaseSource::GitHubReleaseSource(Policy policy, Version current, std::unique_ptr<MetadataTransport> transport,
    Clock monotonic, Clock utc) : policy_(std::move(policy)), current_(std::move(current)), transport_(std::move(transport)),
    monotonic_(std::move(monotonic)), utc_(std::move(utc)) {
  ValidateGitHubPolicy(policy_);
  if (!transport_ || !(ParseVersion(current_.text) == current_)) Invalid();
  if (!monotonic_) monotonic_ = [] { return GetTickCount64(); };
  if (!utc_) utc_ = [] { return static_cast<uint64_t>(std::chrono::duration_cast<std::chrono::seconds>(
    std::chrono::system_clock::now().time_since_epoch()).count()); };
}
void GitHubReleaseSource::Gate(uint64_t deadline, const std::atomic<bool>& cancel) const {
  if (cancel.load()) throw Failure("CANCELLED");
  if (monotonic_() >= deadline) throw Failure("TIMEOUT");
}
MetadataResponse GitHubReleaseSource::Get(const std::string& url, bool api, size_t limit, uint64_t deadline,
    const std::atomic<bool>& cancel) {
  Gate(deadline, cancel);
  const auto headers = api ? "Accept: application/vnd.github+json\r\nX-GitHub-Api-Version: 2026-03-10\r\n" :
    "Accept: application/octet-stream\r\n";
  auto response = transport_->Get({url, headers, limit, deadline}, cancel);
  Gate(deadline, cancel);
  if (response.body.size() > limit) Invalid();
  return response;
}
std::string GitHubReleaseSource::Fetch(const std::atomic<bool>& cancel) { return FetchImpl(nullptr, cancel); }
std::string GitHubReleaseSource::FetchFor(const Release& consent, const std::atomic<bool>& cancel) { return FetchImpl(&consent, cancel); }
std::string GitHubReleaseSource::FetchImpl(const Release* consent, const std::atomic<bool>& cancel) {
  const auto start = monotonic_(); if (start > UINT64_MAX - 30000) throw Failure("TIMEOUT");
  const auto deadline = start + 30000;
  const auto latestResponse = Get(kGitHubLatest, true, kApiLimit, deadline, cancel);
  if (latestResponse.status != 200) throw Failure("NETWORK_UNAVAILABLE");
  const auto latest = ParseApi(latestResponse.body, false);
  std::string url = latest.catalog.url, bytes;
  for (unsigned hops = 0;; ++hops) {
    // Expected API size is identity, not the absolute resource cap: replacing
    // the asset with a larger bounded file must still report SOURCE_CHANGED.
    const auto response = Get(url, false, kCatalogLimit, deadline, cancel);
    if (response.status == 301 || response.status == 302 || response.status == 303 || response.status == 307 || response.status == 308) {
      if (hops >= 3) throw Failure("SOURCE_UNTRUSTED");
      url = ResolveDownloadRedirect(policy_, url, response.location); continue;
    }
    if (response.status != 200) throw Failure("NETWORK_UNAVAILABLE");
    bytes = response.body; break;
  }
  if (bytes.size() != latest.catalog.size || sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()) != latest.catalog.hash)
    throw Failure("SOURCE_CHANGED");
  const auto catalog = ParseCatalog(bytes, policy_, utc_());
  if (catalog.protocol != 2) Invalid();
  const Release* selected = nullptr;
  for (const auto& release : catalog.releases) {
    if (latest.version < release.version || AssetUrl(release.url, release.version, "ServerDeckSetup.exe") != release.url) Invalid();
    if (release.version == latest.version) selected = &release;
  }
  if (!selected) Invalid(); CheckSetup(*selected, latest);
  if (!consent && current_ < selected->version && !Compatible(*selected, policy_)) throw Failure("RELEASE_INCOMPATIBLE");
  if (consent) {
    const auto* exact = FindConsented(catalog, *consent, policy_);
    if (!(exact->version == latest.version)) {
      const auto targetResponse = Get(kTagPrefix + Tag(exact->version), true, kApiLimit, deadline, cancel);
      if (targetResponse.status == 404) throw Failure("RELEASE_REVOKED");
      if (targetResponse.status != 200) throw Failure("NETWORK_UNAVAILABLE");
      CheckSetup(*exact, ParseApi(targetResponse.body, true));
    }
  }
  Gate(deadline, cancel); return bytes;
}
}  // namespace sd::updates
