#include "mcp_boundary.h"
#include "credential_file.h"
#include <condition_variable>
#include <cstring>
#include <future>
#include <iostream>

using namespace sd::mcp;
namespace {
void Require(bool value) { if (!value) throw std::runtime_error("native boundary unit assertion"); }
template<class F> void Reject(F run) { bool rejected = false; try { run(); } catch (...) { rejected = true; } Require(rejected); }
template<class F> void Stage(int code, F run) { bool failed = false; try { run(); } catch (const BoundaryFailure& e) { Require(e.code == code); failed = true; } Require(failed); }
const std::string client = "00000001-0000-4000-8000-000000000000", epoch = "00000002-0000-4000-8000-000000000000";
struct BridgeFixture {
  BridgePorts ports; std::vector<std::string> calls; std::string proof;
  uint32_t actualPid = 42; uint64_t actualCreation = 1234567890123456ULL;
  std::string actualUser = "synthetic-user", actualLogon = "synthetic-logon";
  bool inspectionFails = false, missingOwner = false, missingPipe = false, badAcl = false, badReparse = false, dpapiFails = false, badVersion = false;
  BridgeFixture() {
    ports.userSid = [] { return "synthetic-user"; }; ports.logonSid = [] { return "synthetic-logon"; };
    ports.readPrivate = [&](const std::string& path, size_t maximum) {
      Require(maximum == 16384);
      if (path == "mcp/owner.json") {
        calls.push_back("owner"); if (missingOwner) throw std::runtime_error("synthetic owner absent");
        return Encode(Json::Object{{"protocolVersion",1},{"ownerEpoch",epoch},{"pid",42},{"processCreationTime","1234567890123456"},
          {"userSid","synthetic-user"},{"logonSid","synthetic-logon"},{"pipeName","\\\\.\\pipe\\ServerDeck.Mcp." + epoch + ".0123456789abcdef0123456789abcdef"}});
      }
      Require(path == "mcp/clients/" + client + ".grant"); calls.push_back("grant");
      if (badAcl || badReparse) throw std::runtime_error("synthetic private metadata rejection");
      const std::vector<uint8_t> bytes{3,1,4};
      return Encode(Json::Object{{"version",1},{"clientId",client},{"grantVersion",7},{"protectedSecret",EncodeBase64(bytes.data(),bytes.size())}});
    };
    ports.connect = [&](const OwnerDescriptor&) { calls.push_back("connect"); if (missingPipe) throw std::runtime_error("synthetic absent pipe"); };
    ports.verifyPeer = [&](const OwnerDescriptor& expected) { calls.push_back("verify");
      return !inspectionFails && expected.pid == actualPid && expected.creation == actualCreation && expected.userSid == actualUser && expected.logonSid == actualLogon; };
    ports.unprotect = [&](const std::vector<uint8_t>& bytes, const std::string& purpose) {
      calls.push_back("unprotect"); Require(bytes == std::vector<uint8_t>({3,1,4})); Require(purpose == "mcp-grant.v1:" + client);
      if (dpapiFails) throw std::runtime_error("synthetic DPAPI failure"); return std::vector<uint8_t>(32,9);
    };
    ports.sendFrame = [&](const std::string& value) { calls.push_back("send"); const auto frame = Decode(value);
      Require(frame.at("kind").string() == "auth"); Require(frame.at("ownerEpoch").string() == epoch); proof = frame.at("secret").string(); };
    ports.readFrame = [&] { calls.push_back("receive"); return Encode(Json::Object{{"kind","authorized"},{"version",1},{"grantVersion",badVersion?6:7},{"expiresAt",1700000000000LL}}); };
  }
};
void HandshakeUnits() {
  { BridgeFixture f; const auto result = AuthenticateBridge(f.ports,client); Require(result.version == 7); Require(f.proof.size() == 43);
    Require(f.calls == std::vector<std::string>({"owner","connect","verify","grant","unprotect","send","receive"})); }
  for (int fault = 0; fault < 5; ++fault) {
    BridgeFixture f;
    if (fault == 0) ++f.actualPid; else if (fault == 1) ++f.actualCreation; else if (fault == 2) f.actualUser = "foreign";
    else if (fault == 3) f.actualLogon = "foreign-logon"; else f.inspectionFails = true;
    Stage(21,[&] { AuthenticateBridge(f.ports,client); });
    Require(f.calls == std::vector<std::string>({"owner","connect","verify"})); Require(f.proof.empty());
  }
  { BridgeFixture f; f.missingOwner = true; Stage(20,[&] { AuthenticateBridge(f.ports,client); }); Require(f.calls == std::vector<std::string>({"owner"})); }
  { BridgeFixture f; f.missingPipe = true; Stage(20,[&] { AuthenticateBridge(f.ports,client); }); Require(f.calls == std::vector<std::string>({"owner","connect"})); }
  for (int fault = 0; fault < 3; ++fault) {
    BridgeFixture f; f.badAcl = fault == 0; f.badReparse = fault == 1; f.dpapiFails = fault == 2;
    Stage(22,[&] { AuthenticateBridge(f.ports,client); }); Require(f.proof.empty());
    Require(std::find(f.calls.begin(),f.calls.end(),"send") == f.calls.end());
  }
  { BridgeFixture f; f.badVersion = true; Stage(22,[&] { AuthenticateBridge(f.ports,client); }); }
  Require(PrivateMetadataPolicy("u","u",false,true,{"u","S-1-5-18","S-1-5-32-544"}));
  Require(!PrivateMetadataPolicy("u","u",true,true,{"u"})); Require(!PrivateMetadataPolicy("u","u",false,false,{}));
  Require(!PrivateMetadataPolicy("u","other",false,true,{"u"})); Require(!PrivateMetadataPolicy("u","u",false,true,{"S-1-1-0"}));
}
void ClientPeerUnits() {
  for (int fault = 0; fault < 6; ++fault) {
    int impersonates = 0, queries = 0, reverts = 0;
    ClientPeerPorts p;
    p.processIdentity = [&] { return fault != 0; };
    p.impersonate = [&] { ++impersonates; return fault != 1; };
    p.tokenIdentity = [&] { ++queries; if (fault == 2) throw std::runtime_error("synthetic token query failure");
      return std::make_pair(fault == 3 ? std::string("other") : std::string("u"), fault == 4 ? std::string("other") : std::string("l")); };
    p.revert = [&] { ++reverts; return fault != 5; };
    Require(VerifyClientPeer(p,"u","l") == (fault == 5 ? ClientPeerResult::revertFailed : ClientPeerResult::denied));
    Require(reverts == (fault >= 2 ? 1 : 0)); Require(queries == (fault >= 2 ? 1 : 0)); Require(impersonates == (fault ? 1 : 0));
  }
}
void IoUnits() {
  Require(sd::AdmitKeyFile(false,false,0) == sd::KeyFileAdmission::readFailed);
  Require(sd::AdmitKeyFile(true,false,1024) == sd::KeyFileAdmission::readFailed);
  Require(sd::AdmitKeyFile(true,true,0) == sd::KeyFileAdmission::invalidSize);
  Require(sd::AdmitKeyFile(true,true,1024 * 1024 + 1) == sd::KeyFileAdmission::invalidSize);
  Require(sd::AdmitKeyFile(true,true,1024 * 1024) == sd::KeyFileAdmission::ready);
  FrameReservations reservations;
  for (int i = 0; i < 16; ++i) Require(reservations.Admit()); Require(!reservations.Admit());
  Require(reservations.count() == 16); Require(reservations.Acknowledge()); Require(reservations.Admit());
  for (int i = 0; i < 16; ++i) Require(reservations.Acknowledge()); Require(!reservations.Acknowledge());
  std::string written; size_t writes = 0;
  WriteFrame("{\"x\":1}",[&](const char* bytes,size_t count) { ++writes; const auto n = std::min(size_t{2},count); written.append(bytes,n); return n; });
  Require(written == "{\"x\":1}\n" && writes > 1);
  Reject([] { WriteFrame("{}",[](const char*,size_t) { return size_t{0}; }); });
  const auto original = std::string("{\"x\":1}"); WriteFrame(original,[](const char*,size_t n) { return n; }); Require(original == "{\"x\":1}");
  FrameReader reader([] { return uint64_t{0}; }); size_t offset = 0;
  const std::string input = "{\"x\":1}\n{\"y\":2}\n";
  const ReadFrameBytes oneByte = [&](char* bytes,size_t,uint32_t) { if (offset == input.size()) return size_t{0}; *bytes = input[offset++]; return size_t{1}; };
  Require(Decode(reader.Read(oneByte)).at("x").integer() == 1); Require(Decode(reader.Read(oneByte)).at("y").integer() == 2); Reject([&] { reader.Read(oneByte); });
  uint64_t now = 0; FrameReader deadline([&] { return now; });
  Stage(23,[&] { deadline.Read([&](char* bytes,size_t,uint32_t) { *bytes = ' '; now += 5000; return size_t{1}; },5000); });
}
void StdioUnits() {
  std::string input = "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}\ninvalid\n[]\n"; size_t offset = 0;
  std::vector<std::string> sent,output;
  PumpStdioInput([&](char* bytes,size_t,uint32_t) { if (offset == input.size()) return size_t{0}; *bytes = input[offset++]; return size_t{1}; },
    [&](const std::string& v) { sent.push_back(v); },[&](const std::string& v) { output.push_back(v); },[] { return false; });
  Require(sent.size() == 1 && output.size() == 2); Require(Decode(sent[0]).at("kind").string() == "mcp");
  Require(Decode(output[0]).at("error").at("code").integer() == -32700); Require(Decode(output[1]).at("error").at("code").integer() == -32600);
  size_t receives = 0; std::vector<std::string> stdoutLines;
  PumpStdioOutput([&] { if (receives++) throw EndOfStream{}; return std::string(R"({"kind":"mcp","payload":{"jsonrpc":"2.0","id":1,"result":{}}})"); },
    [&](const std::string& value) { stdoutLines.push_back(value); });
  Require(stdoutLines.size() == 1); const auto result = Decode(stdoutLines[0]); Require(result.at("jsonrpc").string() == "2.0"); Require(result.object().find("kind") == result.object().end());
  Reject([] { PumpStdioOutput([] { return std::string(R"({"kind":"authorized","version":1})"); },[](const std::string&) {}); });
  size_t reads = 0;
  Stage(23,[&] { PumpStdioInput([&](char* bytes,size_t,uint32_t) { if (reads++) return size_t{0}; *bytes = '{'; return size_t{1}; },
    [](const std::string&) {},[](const std::string&) {},[] { return false; }); });
}
void WorkerUnits() {
  std::mutex mutex; std::condition_variable cv; bool cancel = false, permit = false; int started = 0, exited = 0, released = 0;
  OwnedIoWorkers workers([&] { std::lock_guard<std::mutex> lock(mutex); cancel = true; cv.notify_all(); },[&] { Require(exited == 2); ++released; });
  const auto body = [&] { std::unique_lock<std::mutex> lock(mutex); ++started; cv.notify_all(); cv.wait(lock,[&] { return permit; }); ++exited; };
  workers.Start(body,body);
  { std::unique_lock<std::mutex> lock(mutex); cv.wait(lock,[&] { return started == 2; }); }
  auto close = std::async(std::launch::async,[&] { workers.Close(); });
  { std::unique_lock<std::mutex> lock(mutex); cv.wait(lock,[&] { return cancel; }); Require(released == 0); permit = true; cv.notify_all(); }
  auto retry = std::async(std::launch::async,[&] { workers.Close(); }); close.get(); retry.get(); Require(released == 1); workers.Close(); Require(released == 1);
}
}
int main() {
  try { HandshakeUnits(); ClientPeerUnits(); IoUnits(); StdioUnits(); WorkerUnits();
    std::cout << "Native bridge/peer/metadata/partial IO/stdio/worker synthetic units passed; no app, pipe peer, DPAPI or subprocess integration.\n"; return 0;
  } catch (...) { std::cerr << "Native boundary unit failed\n"; return 1; }
}
