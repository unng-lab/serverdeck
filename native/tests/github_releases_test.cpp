#include "github_releases.h"
#include "mcp_json.h"
#include "security.h"
#include <bcrypt.h>
#include <iostream>

namespace {
using namespace sd::updates;
using sd::mcp::Json;
void Require(bool value, const char* reason) { if (!value) throw std::runtime_error(reason); }
template<class F> void Reject(F action, const char* code) {
  try { action(); } catch (const Failure& error) { Require(std::string(error.what()) == code, error.what()); return; }
  throw std::runtime_error("invalid source accepted");
}
std::string Hash(const std::string& bytes) { return sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size()); }
struct Signer {
  BCRYPT_ALG_HANDLE algorithm = nullptr; BCRYPT_KEY_HANDLE key = nullptr;
  Signer() {
    Require(BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_ECDSA_P256_ALGORITHM, nullptr, 0) >= 0, "algorithm");
    Require(BCryptGenerateKeyPair(algorithm, &key, 256, 0) >= 0 && BCryptFinalizeKeyPair(key, 0) >= 0, "key");
  }
  ~Signer() { if (key) BCryptDestroyKey(key); if (algorithm) BCryptCloseAlgorithmProvider(algorithm, 0); }
  static std::string Hex(const uint8_t* bytes, size_t count) {
    std::string value; constexpr char digits[] = "0123456789abcdef";
    for (size_t i = 0; i < count; ++i) { value += digits[bytes[i] >> 4]; value += digits[bytes[i] & 15]; }
    return value;
  }
  Policy PolicyValue() {
    uint8_t blob[72]{}; ULONG length = 0;
    Require(BCryptExportKey(key, nullptr, BCRYPT_ECCPUBLIC_BLOB, blob, 72, &length, 0) >= 0 && length == 72, "public");
    return ParsePolicy(sd::mcp::Encode(Json::Object{{"schema", 1}, {"endpoint", kGitHubLatest}, {"storeFormat", 2},
      {"downloadHosts", Json::Array{"github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com", "github-releases.githubusercontent.com"}},
      {"keys", Json::Array{Json::Object{{"id", "unit"}, {"p256", Hex(blob + 8, 64)}}}}}));
  }
  std::string Catalog(const std::vector<Release>& releases, bool legacy = false) {
    std::string bytes = legacy ? "SDRELEASES001\n99990\n100100\n" : "SDRELEASES002\n99990\n";
    bytes += std::to_string(releases.size()) + '\n';
    for (const auto& release : releases) bytes += release.version.text + "\nwindows-x64\n" + std::to_string(release.bootstrapAbi) +
      "\n2\n99900\n" + std::to_string(release.setupSize) + '\n' + release.setupHash + '\n' +
      std::to_string(release.appSize) + '\n' + release.appHash + '\n' + release.url + "\nVGVzdA==\n";
    const auto hash = Hash(bytes); uint8_t digest[32]{}, signature[64]{}; ULONG length = 0;
    for (size_t i = 0; i < 32; ++i) digest[i] = static_cast<uint8_t>(std::stoul(hash.substr(i * 2, 2), nullptr, 16));
    Require(BCryptSignHash(key, nullptr, digest, 32, signature, 64, &length, 0) >= 0 && length == 64, "sign");
    return std::string(legacy ? "SDCATALOG001\nunit\n" : "SDCATALOG002\nunit\n") + Hex(signature, 64) + '\n' + bytes;
  }
};
std::string Tag(const Version& version) { auto tag = "v" + version.text; tag.replace(tag.find('+'), 1, "%2B"); return tag; }
std::string Url(const Version& version, const char* name) { return "https://github.com/unng-lab/serverdeck/releases/download/" + Tag(version) + "/" + name; }
Release Entry(const char* version = "0.2.0+1") {
  Release r; r.version = ParseVersion(version); r.platform = "windows-x64"; r.bootstrapAbi = 1; r.storeFormat = 2;
  r.published = 99900; r.setupSize = 12; r.setupHash = std::string(64, 'a'); r.appSize = 10; r.appHash = std::string(64, 'b');
  r.url = Url(r.version, "ServerDeckSetup.exe"); r.notes = "Test"; return r;
}
Json Asset(const std::string& name, uint64_t size, const std::string& hash, const std::string& url) {
  return Json::Object{{"name", name}, {"state", "uploaded"}, {"size", static_cast<int64_t>(size)}, {"digest", "sha256:" + hash}, {"browser_download_url", url}};
}
Json Api(const Release& release, const std::string& catalog, bool target = false) {
  Json::Array assets{Asset("ServerDeckSetup.exe", release.setupSize, release.setupHash, release.url)};
  if (!target) assets.push_back(Asset("serverdeck-update-catalog.txt", catalog.size(), Hash(catalog), Url(release.version, "serverdeck-update-catalog.txt")));
  return Json::Object{{"tag_name", "v" + release.version.text}, {"draft", false}, {"prerelease", false},
    {"published_at", "2026-11-04T10:15:30Z"}, {"assets", assets}, {"body", "ignored Markdown"}};
}
struct Http : MetadataTransport {
  std::vector<MetadataResponse> responses;
  std::vector<MetadataRequest> requests;
  std::function<void()> after;
  MetadataResponse Get(const MetadataRequest& input, const std::atomic<bool>&) override {
    requests.push_back(input); if (after) after();
    Require(requests.size() <= responses.size(), "unexpected request"); return responses[requests.size() - 1];
  }
};
struct Run {
  uint64_t ticks = 500, utc = 100000 + 365 * 86400;
  std::atomic<bool> cancel{false}; Http* http;
  GitHubReleaseSource source;
  Run(const Policy& policy, std::vector<MetadataResponse> responses)
    : http(new Http), source(policy, ParseVersion("0.1.0+1"), std::unique_ptr<Http>(http), [this] { return ticks; }, [this] { return utc; }) {
    http->responses = std::move(responses);
  }
};
std::vector<MetadataResponse> Responses(const Json& api, const std::string& catalog) { return {{200, {}, sd::mcp::Encode(api)}, {200, {}, catalog}}; }
}
int main() {
  try {
    Signer signer; const auto policy = signer.PolicyValue(); const auto latest = Entry(), old = Entry("0.1.1+1");
    const auto catalog = signer.Catalog({old, latest}); const auto api = Api(latest, catalog);
    {
      Run run(policy, Responses(api, catalog)); Require(run.source.Fetch(run.cancel) == catalog, "latest catalog");
      const auto& requests = run.http->requests;
      Require(requests.size() == 2 && requests[0].url == kGitHubLatest && requests[0].limit == 512 * 1024 &&
        requests[0].headers == "Accept: application/vnd.github+json\r\nX-GitHub-Api-Version: 2026-03-10\r\n" &&
        requests[0].deadline == requests[1].deadline && requests[1].limit == kCatalogLimit &&
        requests[1].url == Url(latest.version, "serverdeck-update-catalog.txt"), "API contract");
    }
    {
      auto responses = Responses(api, catalog); responses.push_back({200, {}, sd::mcp::Encode(Api(old, {}, true))});
      Run run(policy, responses); Require(run.source.FetchFor(old, run.cancel) == catalog && run.http->requests.size() == 3 &&
        run.http->requests.back().url == "https://api.github.com/repos/unng-lab/serverdeck/releases/tags/v0.1.1%2B1", "old consent retargeted");
    }
    for (const auto status : {403u, 404u, 429u, 500u, 302u}) {
      Run run(policy, {{status, "https://other.test", {}}}); Reject([&] { run.source.Fetch(run.cancel); }, "NETWORK_UNAVAILABLE");
      Require(run.http->requests.size() == 1, "hidden retry");
    }
    for (const auto* field : {"draft", "prerelease"}) {
      auto bad = api.object(); bad[field] = true; Run run(policy, Responses(bad, catalog));
      Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
    }
    for (const auto* date : {"2026-02-30T00:00:00Z", "2026-01-01", "2026-01-01T24:00:00Z"}) {
      auto bad = api.object(); bad["published_at"] = date; Run run(policy, Responses(bad, catalog));
      Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
    }
    for (const auto& malformed : {std::string("{\"draft\":false,\"draft\":false}"), std::string(512 * 1024 + 1, 'x')}) {
      Run run(policy, {{200, {}, malformed}}); Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
    }
    {
      auto bad = api.object(); bad["assets"] = Json::Array{}; Run run(policy, Responses(bad, catalog));
      Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
      bad["assets"] = Json::Array(129, Json::Object{{"name", "unrelated"}});
      Run many(policy, Responses(bad, catalog)); Reject([&] { many.source.Fetch(many.cancel); }, "INVALID_CATALOG");
    }
    for (const auto* badUrl : {"https://github.com/other/serverdeck/releases/download/v0.2.0%2B1/ServerDeckSetup.exe",
        "https://github.com/unng-lab/serverdeck/releases/download/v0.2.0%252B1/ServerDeckSetup.exe",
        "https://github.com/unng-lab/serverdeck/releases/download/v0.2.0%2B1/ServerDeckSetup.exe?token=x"}) {
      auto bad = api.object(); auto assets = std::get<Json::Array>(bad["assets"].value); auto asset = assets.front().object();
      asset["browser_download_url"] = badUrl; assets.front() = asset; bad["assets"] = assets;
      Run run(policy, Responses(bad, catalog)); Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
    }
    {
      auto bad = api.object(); auto assets = std::get<Json::Array>(bad["assets"].value); auto asset = assets.front().object();
      auto url = latest.url; url.replace(url.find("%2B"), 3, "+"); asset["browser_download_url"] = url;
      assets.front() = asset; bad["assets"] = assets; Run run(policy, Responses(bad, catalog)); Require(run.source.Fetch(run.cancel) == catalog, "literal plus tag");
    }
    {
      auto bad = api.object(); auto assets = std::get<Json::Array>(bad["assets"].value); assets.push_back(assets.front()); bad["assets"] = assets;
      Run run(policy, Responses(bad, catalog)); Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
    }
    {
      auto different = latest; different.setupHash.assign(64, 'c');
      Run run(policy, Responses(Api(different, catalog), catalog)); Reject([&] { run.source.Fetch(run.cancel); }, "SOURCE_CHANGED");
      auto tampered = catalog; tampered.back() = 'x'; Run bytes(policy, Responses(api, tampered));
      Reject([&] { bytes.source.Fetch(bytes.cancel); }, "SOURCE_CHANGED");
      Run signature(policy, Responses(Api(latest, tampered), tampered));
      Reject([&] { signature.source.Fetch(signature.cancel); }, "INVALID_CATALOG");
      tampered = catalog; tampered[tampered.size() - 3] = 'A'; Run signedBytes(policy, Responses(Api(latest, tampered), tampered));
      Reject([&] { signedBytes.source.Fetch(signedBytes.cancel); }, "SOURCE_UNTRUSTED");
      for (const auto& replacement : {signer.Catalog({Entry("0.1.0+2"), old, latest}), signer.Catalog({latest})}) {
        Require(replacement.size() != catalog.size() && replacement.size() < kCatalogLimit, "replacement fixture bounds");
        Run changedSize(policy, Responses(api, replacement));
        Reject([&] { changedSize.source.Fetch(changedSize.cancel); }, "SOURCE_CHANGED");
      }
      Run oversized(policy, Responses(api, std::string(kCatalogLimit + 1, 'x')));
      Reject([&] { oversized.source.Fetch(oversized.cancel); }, "INVALID_CATALOG");
    }
    {
      const auto legacy = signer.Catalog({latest}, true); Run run(policy, Responses(Api(latest, legacy), legacy)); run.utc = 100000;
      Reject([&] { run.source.Fetch(run.cancel); }, "INVALID_CATALOG");
      auto incompatible = latest; incompatible.bootstrapAbi = 2; const auto bytes = signer.Catalog({old, incompatible});
      Run other(policy, Responses(Api(incompatible, bytes), bytes)); Reject([&] { other.source.Fetch(other.cancel); }, "RELEASE_INCOMPATIBLE");
      auto responses = Responses(Api(incompatible, bytes), bytes); responses.push_back({200, {}, sd::mcp::Encode(Api(old, {}, true))});
      Run retained(policy, responses); Require(retained.source.FetchFor(old, retained.cancel) == bytes, "incompatible new latest revoked old consent");
      const auto noLatest = signer.Catalog({old}); Run missing(policy, Responses(Api(latest, noLatest), noLatest));
      Reject([&] { missing.source.Fetch(missing.cancel); }, "INVALID_CATALOG");
    }
    for (const auto status : {404u, 403u}) {
      auto responses = Responses(api, catalog); responses.push_back({status, {}, {}}); Run run(policy, responses);
      Reject([&] { run.source.FetchFor(old, run.cancel); }, status == 404 ? "RELEASE_REVOKED" : "NETWORK_UNAVAILABLE");
    }
    {
      auto responses = Responses(api, catalog); auto revoked = Api(old, {}, true).object(); revoked["draft"] = true;
      responses.push_back({200, {}, sd::mcp::Encode(revoked)}); Run run(policy, responses);
      Reject([&] { run.source.FetchFor(old, run.cancel); }, "RELEASE_REVOKED");
      const auto removed = signer.Catalog({latest}); Run missing(policy, Responses(Api(latest, removed), removed));
      Reject([&] { missing.source.FetchFor(old, missing.cancel); }, "RELEASE_REVOKED");
      auto changed = old; changed.notes = "changed"; Run mismatch(policy, Responses(api, catalog));
      Reject([&] { mismatch.source.FetchFor(changed, mismatch.cancel); }, "SOURCE_CHANGED");
      auto wrongBytes = old; wrongBytes.setupSize++; responses = Responses(api, catalog);
      responses.push_back({200, {}, sd::mcp::Encode(Api(wrongBytes, {}, true))}); Run changedTarget(policy, responses);
      Reject([&] { changedTarget.source.FetchFor(old, changedTarget.cancel); }, "SOURCE_CHANGED");
      auto missingAsset = Api(old, {}, true).object(); missingAsset["assets"] = Json::Array{}; responses = Responses(api, catalog);
      responses.push_back({200, {}, sd::mcp::Encode(missingAsset)}); Run assetRemoved(policy, responses);
      Reject([&] { assetRemoved.source.FetchFor(old, assetRemoved.cancel); }, "RELEASE_REVOKED");
      Run exactLatest(policy, Responses(api, catalog)); Require(exactLatest.source.FetchFor(latest, exactLatest.cancel) == catalog &&
        exactLatest.http->requests.size() == 2, "latest consent adds unnecessary target request");
    }
    {
      auto responses = Responses(api, catalog); responses.insert(responses.begin() + 1, {302, "https://release-assets.githubusercontent.com/catalog", {}});
      Run run(policy, responses); Require(run.source.Fetch(run.cancel) == catalog && run.http->requests.size() == 3, "allowed CDN redirect");
      for (const auto* location : {"http://github.com/file", "https://evil.example/catalog", "https://user:pw@github.com/file"}) {
        auto bad = responses; bad[1].location = location; Run other(policy, bad); Reject([&] { other.source.Fetch(other.cancel); }, "SOURCE_UNTRUSTED");
      }
      auto endless = Responses(api, catalog); endless.resize(5, {302, "/again", {}}); endless[1] = {302, "/again", {}};
      Run loop(policy, endless); Reject([&] { loop.source.Fetch(loop.cancel); }, "SOURCE_UNTRUSTED");
    }
    {
      Run run(policy, Responses(api, catalog)); run.http->after = [&] { run.ticks += 16000; };
      Reject([&] { run.source.Fetch(run.cancel); }, "TIMEOUT"); Require(run.http->requests.size() == 2, "separate deadline per response");
      Run cancelled(policy, Responses(api, catalog)); cancelled.http->after = [&] { cancelled.cancel = true; };
      Reject([&] { cancelled.source.Fetch(cancelled.cancel); }, "CANCELLED");
      Run early(policy, {}); early.cancel = true; Reject([&] { early.source.Fetch(early.cancel); }, "CANCELLED");
      Require(early.http->requests.empty(), "cancel started request");
    }
    {
      auto bad = policy; bad.endpoint = "https://updates.example/catalog"; Reject([&] { ValidateGitHubPolicy(bad); }, "INVALID_CATALOG");
      Reject([&] { MakeWinHttpCatalogSource(bad, ParseVersion("0.1.0+1")); }, "INVALID_CATALOG");
      bad = policy; bad.downloadHosts.push_back("other.example"); Reject([&] { ValidateGitHubPolicy(bad); }, "INVALID_CATALOG");
    }
    std::cout << "GitHub release synthetic unit checks passed\n"; return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
