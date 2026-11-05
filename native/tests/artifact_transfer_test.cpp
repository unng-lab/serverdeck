#include "artifact_transfer.h"
#include "security.h"
#include <algorithm>
#include <cstring>
#include <iostream>
#include <map>
#include <vector>

namespace {
void Require(bool condition, const char* text) { if (!condition) throw std::runtime_error(text); }
template<class F> void Reject(F action, const char* code) {
  try { action(); } catch (const sd::updates::Failure& error) { Require(std::string(error.what()) == code, "wrong failure code"); return; }
  throw std::runtime_error("invalid transfer accepted");
}
struct Response {
  sd::updates::ArtifactHeaders headers{200, {}, {}};
  std::string body;
  uint64_t headerDelay = 0, readDelay = 0;
  size_t chunk = 65536;
  bool oversizedRead = false;
};
struct Transport : sd::updates::ArtifactTransport {
  std::map<std::string, Response> responses;
  std::vector<std::string> opened;
  uint64_t now = 1000;
  size_t closed = 0;
  struct Request : sd::updates::ArtifactRequest {
    Transport& owner; Response response; size_t position = 0;
    Request(Transport& parent, Response value) : owner(parent), response(std::move(value)) {}
    ~Request() override { ++owner.closed; }
    sd::updates::ArtifactHeaders Start(uint64_t, const std::atomic<bool>&) override {
      owner.now += response.headerDelay; return response.headers;
    }
    size_t Read(uint8_t* bytes, size_t capacity, uint64_t, const std::atomic<bool>&) override {
      owner.now += response.readDelay;
      if (response.oversizedRead) return capacity + 1;
      const auto count = std::min({capacity, response.chunk, response.body.size() - position});
      if (count) std::memcpy(bytes, response.body.data() + position, count);
      position += count; return count;
    }
  };
  std::unique_ptr<sd::updates::ArtifactRequest> Open(const std::string& url) override {
    opened.push_back(url);
    const auto found = responses.find(url); if (found == responses.end()) throw sd::updates::Failure("NETWORK_UNAVAILABLE");
    return std::make_unique<Request>(*this, found->second);
  }
};
sd::updates::Release MakeRelease(const std::string& bytes) {
  sd::updates::Release value;
  value.version = sd::updates::ParseVersion("0.2.0+1"); value.platform = "windows-x64";
  value.bootstrapAbi = 1; value.storeFormat = 2; value.setupSize = bytes.size();
  value.setupHash = sd::Sha256(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size());
  value.url = "https://assets.example/build/setup.exe"; return value;
}
}
int main() {
  using namespace sd::updates;
  try {
    Policy policy; policy.storeFormat = 2; policy.downloadHosts = {"assets.example", "cdn.example"};
    const std::string body(131073, 'x'); const auto release = MakeRelease(body);
    std::atomic<bool> cancel{false};
    const auto run = [&](Transport& transport, const Release& target, const ArtifactSink& sink, ArtifactProgress progress = {}) {
      TransferArtifact(policy, target, transport, cancel, sink, std::move(progress), [&] { return transport.now; });
    };
    for (const bool known : {false, true}) {
      Transport transport; Response response; response.body = body;
      if (known) response.headers.length = body.size();
      transport.responses[release.url] = response;
      std::string received; size_t chunks = 0; uint64_t progressBytes = 0;
      run(transport, release, [&](const uint8_t* bytes, size_t count) {
        Require(count <= 65536, "chunk limit"); received.append(reinterpret_cast<const char*>(bytes), count); ++chunks;
      }, [&](uint64_t count, std::optional<uint64_t> total) {
        Require(total.has_value() == known && (!known || *total == body.size()), "observed length synthesized");
        Require(count >= progressBytes, "progress reversed"); progressBytes = count;
      });
      Require(received == body && chunks == 3 && progressBytes == body.size() && transport.closed == 1, "verified stream");
    }
    {
      Transport transport; Response redirect; redirect.headers.status = 302; redirect.headers.location = "../next/setup.exe";
      transport.responses[release.url] = redirect;
      redirect.headers.location = "//cdn.example/step/file";
      transport.responses["https://assets.example/next/setup.exe"] = redirect;
      redirect.headers.location = "../final.exe";
      transport.responses["https://cdn.example/step/file"] = redirect;
      Response final; final.body = body; transport.responses["https://cdn.example/final.exe"] = final;
      run(transport, release, [](const uint8_t*, size_t) {});
      Require(transport.opened.size() == 4 && transport.closed == 4, "three redirect chain");
    }
    for (const auto* location : {"http://assets.example/setup.exe", "https://foreign.example/a", "https://user:pass@assets.example/a",
        "https://127.0.0.1/a", "https://0x7f.0.0.1/a", "https://assets.example:444/a", "/a#fragment", "/\\foreign/a", ""}) {
      Transport transport; Response redirect; redirect.headers.status = 307; redirect.headers.location = location;
      transport.responses[release.url] = redirect;
      Reject([&] { run(transport, release, [](const uint8_t*, size_t) {}); }, "SOURCE_UNTRUSTED");
      Require(transport.opened.size() == 1 && transport.closed == 1, "untrusted redirect fetched");
    }
    {
      Transport transport; Response redirect; redirect.headers.status = 308; redirect.headers.location = release.url;
      transport.responses[release.url] = redirect;
      Reject([&] { run(transport, release, [](const uint8_t*, size_t) {}); }, "SOURCE_UNTRUSTED");
      Require(transport.opened.size() == 4 && transport.closed == 4, "redirect limit");
    }
    for (int defect = 0; defect < 5; ++defect) {
      Transport transport; Response response; response.body = body;
      if (defect == 0) response.body.pop_back();
      if (defect == 1) response.body += 'x';
      if (defect == 2) response.body[0] = 'y';
      if (defect == 3) response.headers.length = body.size() + 1;
      if (defect == 4) response.oversizedRead = true;
      transport.responses[release.url] = response;
      Reject([&] { run(transport, release, [](const uint8_t*, size_t) {}); }, "INVALID_ARTIFACT");
      Require(transport.closed == 1, "failed request not closed");
    }
    for (const auto status : {206u, 401u, 500u}) {
      Transport transport; Response response; response.headers.status = status; response.body = body;
      transport.responses[release.url] = response; size_t writes = 0;
      Reject([&] { run(transport, release, [&](const uint8_t*, size_t) { ++writes; }); }, "NETWORK_UNAVAILABLE");
      Require(writes == 0 && transport.closed == 1, "non-full response used as artifact");
    }
    {
      Transport transport; Response response; response.body = body; transport.responses[release.url] = response;
      size_t chunks = 0;
      Reject([&] { run(transport, release, [&](const uint8_t*, size_t) { ++chunks; cancel = true; }); }, "CANCELLED");
      Require(chunks == 1 && transport.closed == 1, "cancellation continued writing"); cancel = false;
      Reject([&] { run(transport, release, [](const uint8_t*, size_t) { throw Failure("STORAGE_IO"); }); }, "STORAGE_IO");
      cancel = true; const auto requests = transport.opened.size();
      Reject([&] { run(transport, release, [](const uint8_t*, size_t) {}); }, "CANCELLED");
      Require(transport.opened.size() == requests, "pre-cancel request started"); cancel = false;
    }
    for (int timeout = 0; timeout < 3; ++timeout) {
      Transport transport; Response response;
      auto target = MakeRelease(std::string(32, 'x')); response.body = std::string(32, 'x');
      if (timeout == 0) response.headerDelay = 30001;
      if (timeout == 1) response.readDelay = 60001;
      if (timeout == 2) { response.readDelay = 59000; response.chunk = 1; }
      transport.responses[target.url] = response;
      Reject([&] { run(transport, target, [](const uint8_t*, size_t) {}); }, "TIMEOUT");
      Require(transport.closed == 1, "timeout request not closed");
    }
    {
      Transport transport; auto invalid = release; invalid.url = "https://foreign.example/setup";
      Reject([&] { run(transport, invalid, [](const uint8_t*, size_t) {}); }, "SOURCE_UNTRUSTED");
      invalid = release; invalid.setupSize = kArtifactLimit + 1;
      Reject([&] { run(transport, invalid, [](const uint8_t*, size_t) {}); }, "INVALID_ARTIFACT");
      Require(transport.opened.empty(), "invalid artifact accessed network");
    }
    std::cout << "artifact transfer synthetic units passed\n"; return 0;
  } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
