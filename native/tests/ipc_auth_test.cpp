#include "mcp_json.h"
#include <iostream>

namespace {
void Require(bool value) { if (!value) throw std::runtime_error("unit assertion"); }
template<class F> void Reject(F run) { bool rejected = false; try { run(); } catch (...) { rejected = true; } Require(rejected); }
}
int main() {
  using namespace sd::mcp;
  try {
    const auto auth = Decode(R"({"kind":"auth","version":1,"clientId":"00000001-0000-4000-8000-000000000000","grantVersion":1,"ownerEpoch":"00000002-0000-4000-8000-000000000000","secret":"synthetic"})");
    Require(auth.at("version").integer() == 1); Require(CanonicalUuid(auth.at("clientId").string()));
    Require(Decode(Encode(auth)).at("ownerEpoch").string() == auth.at("ownerEpoch").string());
    Reject([] { Decode(R"({"kind":"auth","kind":"mcp"})"); });
    Reject([] { Decode("{\"secret\":\"\xc0\xaf\"}"); });
    Reject([] { Decode(R"({"x":"\ud800"})"); });
    Reject([] { Decode(R"({"x":"\udc00"})"); });
    Require(Decode(R"({"x":"\ud83d\ude00"})").at("x").string() == "\xf0\x9f\x98\x80");
    for (const auto* invalid : {"01", "-01", "1.", "1e", "1e+", "NaN", "Infinity", "[1,]", "{\"x\":1,}", "{}true"}) Reject([&] { Decode(invalid); });
    Require(Decode("9007199254740991").integer() == 9007199254740991LL);
    Require(!CanonicalUuid("00000001-0000-4000-8000-000000000000/.."));
    std::string deep(42, '['); deep += '0'; deep += std::string(42, ']'); Reject([&] { Decode(deep); });
    Reject([] { Decode(std::string(kFrameBytes, ' ')); });
    LineBuffer fragmented; std::string line;
    const std::string packet = "{\"x\":\"\xf0\x9f\x98\x80\"}\n{\"y\":2}\r\n";
    for (const auto c : packet) fragmented.Push(&c, 1);
    Require(fragmented.Take(line)); Require(Decode(line).at("x").string() == "\xf0\x9f\x98\x80");
    Require(fragmented.Take(line)); Require(Decode(line).at("y").integer() == 2); Require(!fragmented.Take(line));
    LineBuffer full; const std::string maximum(kFrameBytes - 1, ' '); full.Push(maximum.data(), maximum.size()); full.Push("\n", 1);
    Require(full.Take(line)); Require(line.size() == kFrameBytes - 1); Require(full.capacity() == kFrameBytes);
    LineBuffer overflow; overflow.Push(maximum.data(), maximum.size()); Reject([&] { overflow.Push("xx", 2); });
    LineBuffer invalidUtf8; const char invalid[] = {'\xe0', '\x80', '\x80', '\n'}; invalidUtf8.Push(invalid, sizeof(invalid)); Reject([&] { invalidUtf8.Take(line); });
    std::cout << "Pure IPC codec/framing unit fixtures passed; no pipe/process/app/DPAPI integration executed.\n";
    return 0;
  } catch (...) { std::cerr << "IPC codec unit failed\n"; return 1; }
}
