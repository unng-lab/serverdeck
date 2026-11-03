#include "../../windows/runner/platform_channel.h"
#include <shellapi.h>
#include <wincrypt.h>
#include <iostream>
#include <stdexcept>

namespace {
using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
struct Outcome { V value; std::string error; bool replied = false; };
class Capture : public flutter::MethodResult<V> {
 public:
  explicit Capture(Outcome& outcome) : outcome_(outcome) {}
 protected:
  void SuccessInternal(const V* value) override { outcome_.replied = true; if (value) outcome_.value = *value; }
  void ErrorInternal(const std::string& code, const std::string&, const V*) override {
    outcome_.replied = true; outcome_.error = code;
  }
  void NotImplementedInternal() override { outcome_.replied = true; outcome_.error = "NOT_IMPLEMENTED"; }
 private:
  Outcome& outcome_;
};
class Messenger : public flutter::BinaryMessenger {
 public:
  bool registered = false;
  flutter::BinaryMessageHandler incoming;
  mutable std::vector<M> events;
  void Send(const std::string&, const uint8_t* bytes, size_t size,
            flutter::BinaryReply = nullptr) const override {
    const auto call = flutter::StandardMethodCodec::GetInstance().DecodeMethodCall(bytes, size);
    if (call && call->method_name() == "platform.event") events.push_back(std::get<M>(*call->arguments()));
  }
  void SetMessageHandler(const std::string&, flutter::BinaryMessageHandler handler) override {
    registered = static_cast<bool>(handler);
    incoming = std::move(handler);
  }
  Outcome Call(const std::string& name, M arguments) {
    const auto& codec = flutter::StandardMethodCodec::GetInstance();
    const auto bytes = codec.EncodeMethodCall(flutter::MethodCall<V>(name, std::make_unique<V>(arguments)));
    Outcome outcome;
    Capture capture(outcome);
    incoming(bytes->data(), bytes->size(), [&](const uint8_t* reply, size_t size) {
      if (!codec.DecodeAndProcessResponseEnvelope(reply, size, &capture))
        throw std::runtime_error("Invalid reply codec");
    });
    if (!outcome.replied) throw std::runtime_error("Missing native reply");
    return outcome;
  }
};
DWORD HandleCount() {
  DWORD count = 0;
  if (!GetProcessHandleCount(GetCurrentProcess(), &count)) throw std::runtime_error("Handle count");
  return count;
}
}
int main() {
  wchar_t temp[MAX_PATH]{};
  if (!GetTempPathW(MAX_PATH, temp)) return 1;
  const auto root = std::filesystem::path(temp) / (L"ServerDeckPlatformTest-" + sd::Uuid());
  sd::SecureDirectory(root);
  const auto rootText = root.wstring();
  ServerDeckHostArgsV1 args{sizeof(ServerDeckHostArgsV1), 1, L"C:\\synthetic",
    rootText.c_str(), L"C:\\synthetic\\ServerDeck.exe", L"12345678-1234-4234-8234-123456789abc",
    nullptr, nullptr, 0};
  // Warm system libraries before measuring only this object's HANDLE lifetime.
  NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon);
  Shell_NotifyIconW(NIM_DELETE, &icon);
  LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(101));
  RegisterWindowMessageW(L"TaskbarCreated");
  try {
    for (int failure = 1; failure <= 3; ++failure) {
      Messenger messenger;
      int events = 0;
      PlatformChannelHooks hooks;
      hooks.createEvent = [&] {
        return ++events == failure ? static_cast<HANDLE>(nullptr) : CreateEventW(nullptr, TRUE, FALSE, nullptr);
      };
      const DWORD before = HandleCount();
      bool rejected = false;
      try { PlatformChannel channel(nullptr, &messenger, args, hooks); }
      catch (...) { rejected = true; }
      if (!rejected || messenger.registered || HandleCount() != before) return 2;
    }
    Messenger messenger;
    PlatformChannelHooks hooks;
    hooks.startWorker = [](std::function<void()>) -> std::thread {
      throw std::runtime_error("Injected thread startup failure");
    };
    const DWORD before = HandleCount();
    bool rejected = false;
    try { PlatformChannel channel(nullptr, &messenger, args, hooks); }
    catch (...) { rejected = true; }
    if (!rejected || messenger.registered || HandleCount() != before) return 3;
    hooks.startWorker = [](std::function<void()>) { return std::thread{}; };
    {
      PlatformChannel channel(nullptr, &messenger, args, hooks);
      if (!messenger.registered) return 4;
      const M epoch{{V("ownerEpoch"), V(sd::Utf8(args.ownerEpoch))}};
      LRESULT result = 0;
      for (int i = 0; i < 40; ++i)
        channel.OnMessage(i % 2 ? kActivationMessage : WM_CLOSE, 0, 0, &result);
      channel.OnMessage(WM_QUERYENDSESSION, 1, 0, &result);
      if (!result || !messenger.events.empty()) return 7;
      const auto snapshot = messenger.Call("runtime.snapshot", epoch);
      const auto& facts = std::get<M>(snapshot.value);
      if (!snapshot.error.empty() || !std::get<bool>(facts.at(V("exitRequested"))) ||
          !std::get<bool>(facts.at(V("osEnding"))) || messenger.events.size() != 32) return 8;
      int64_t previous = 0;
      for (const auto& event : messenger.events) {
        const auto seq = std::get<int64_t>(event.at(V("seq")));
        if (seq <= previous || std::get<std::string>(event.at(V("ownerEpoch"))) != sd::Utf8(args.ownerEpoch)) return 9;
        previous = seq;
      }
      const auto stale = messenger.Call("window.restore", {{V("ownerEpoch"), V("old-owner")}});
      if (stale.error != "STALE_EPOCH") return 10;
      // Staging flush must precede verification and must not publish CURRENT.
      const std::string storeId = "12345678-1234-4234-8234-123456789abc";
      const auto stage = root / (L"data/staging-" + sd::Wide(storeId));
      sd::SecureDirectory(root / L"data");
      sd::SecureDirectory(stage);
      sd::AtomicFile(stage / L"synthetic.db", {1, 2, 3});
      M flush = epoch;
      flush[V("path")] = V("data/flush/" + storeId);
      flush[V("bytes")] = V(std::vector<uint8_t>{});
      if (!messenger.Call("file.flushAtomic", flush).error.empty() ||
          std::filesystem::exists(root / L"data/CURRENT.json") || !std::filesystem::exists(stage)) return 25;
      flush[V("bytes")] = V(std::vector<uint8_t>{1});
      if (messenger.Call("file.flushAtomic", flush).error != "INVALID_ARGUMENT") return 26;
      flush[V("bytes")] = V(std::vector<uint8_t>{});
      flush[V("path")] = V("data/flush/------------------------------------");
      if (messenger.Call("file.flushAtomic", flush).error != "INVALID_ARGUMENT") return 27;
      flush[V("path")] = V("data/publish/" + storeId);
      flush[V("bytes")] = V(std::vector<uint8_t>{9});
      if (!messenger.Call("file.flushAtomic", flush).error.empty()) return 28;
      flush[V("path")] = V("data/flush/" + storeId);
      flush[V("bytes")] = V(std::vector<uint8_t>{});
      if (messenger.Call("file.flushAtomic", flush).error != "STORAGE_IO") return 29;
      M secret = epoch;
      secret[V("bytes")] = V(std::vector<uint8_t>{1, 2, 3, 4});
      secret[V("purpose")] = V("synthetic-test");
      const auto protectedValue = messenger.Call("secret.protect", secret);
      if (!protectedValue.error.empty()) return 11;
      secret[V("bytes")] = protectedValue.value;
      const auto plaintext = messenger.Call("secret.unprotect", secret);
      if (!plaintext.error.empty() || std::get<std::vector<uint8_t>>(plaintext.value) !=
          std::vector<uint8_t>{1,2,3,4}) return 12;
      secret[V("purpose")] = V("wrong-domain");
      if (messenger.Call("secret.unprotect", secret).error != "PROTECTION_UNAVAILABLE") return 13;
      // DPAPI adds overhead: a valid maximum-size plaintext exceeds 1 MiB encrypted.
      const std::vector<uint8_t> maximum(1024 * 1024, 0x53);
      secret[V("purpose")] = V("synthetic-test");
      secret[V("bytes")] = V(maximum);
      const auto maximumProtected = messenger.Call("secret.protect", secret);
      if (!maximumProtected.error.empty() ||
          std::get<std::vector<uint8_t>>(maximumProtected.value).size() <= maximum.size()) return 30;
      secret[V("bytes")] = maximumProtected.value;
      const auto maximumPlain = messenger.Call("secret.unprotect", secret);
      if (!maximumPlain.error.empty() || std::get<std::vector<uint8_t>>(maximumPlain.value) != maximum) return 31;
      secret[V("bytes")] = V(std::vector<uint8_t>(1024 * 1024 + 1, 0x53));
      if (messenger.Call("secret.protect", secret).error != "INVALID_ARGUMENT") return 32;
      secret[V("bytes")] = V(std::vector<uint8_t>(2 * 1024 * 1024 + 1, 0x53));
      if (messenger.Call("secret.unprotect", secret).error != "INVALID_ARGUMENT") return 33;
      // A foreign DPAPI blob may decode above the application's plaintext bound.
      std::vector<uint8_t> oversized(1024 * 1024 + 1, 0x53);
      std::string domain = "synthetic-test";
      DATA_BLOB data{static_cast<DWORD>(oversized.size()), oversized.data()};
      DATA_BLOB entropy{static_cast<DWORD>(domain.size()), reinterpret_cast<BYTE*>(domain.data())};
      DATA_BLOB output{};
      if (!CryptProtectData(&data, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output)) return 34;
      secret[V("bytes")] = V(std::vector<uint8_t>(output.pbData, output.pbData + output.cbData));
      SecureZeroMemory(output.pbData, output.cbData); LocalFree(output.pbData);
      if (messenger.Call("secret.unprotect", secret).error != "PROTECTION_UNAVAILABLE") return 35;
    }
    // DPAPI can retain process-wide system caches. Partial-startup cases above
    // measure HANDLE deltas before using DPAPI; here check borrowed callback cleanup.
    if (messenger.registered) return 5;
    // Loss can precede TaskbarCreated: cached registration must never permit
    // another hide, and the native monitor restores without waiting for Dart.
    {
      Messenger shell;
      bool available = true;
      int starts = 0, stops = 0, probes = 0;
      PlatformChannelHooks monitored;
      monitored.startWorker = [](std::function<void()>) { return std::thread{}; };
      monitored.createTray = [](HWND) { return true; };
      monitored.isTrayAvailable = [&](HWND) { ++probes; return available; };
      monitored.startTrayMonitor = [&](HWND, UINT_PTR id, UINT interval) {
        if (id != kTrayMonitorTimer || interval != kTrayMonitorIntervalMs) return UINT_PTR{0};
        ++starts; return id;
      };
      monitored.stopTrayMonitor = [&](HWND, UINT_PTR id) { if (id == kTrayMonitorTimer) ++stops; };
      const M epoch{{V("ownerEpoch"), V(sd::Utf8(args.ownerEpoch))}};
      {
        PlatformChannel channel(nullptr, &shell, args, monitored);
        shell.Call("runtime.snapshot", epoch);
        if (!std::get<bool>(shell.Call("window.hideToTray", epoch).value) || channel.ShouldShowFirstFrame()) return 14;
        LRESULT result = 0;
        const auto beforeProbes = probes;
        if (channel.OnMessage(WM_TIMER, kTrayMonitorTimer + 1, 0, &result) || probes != beforeProbes) return 15;
        shell.events.clear();
        available = false;
        if (!channel.OnMessage(WM_TIMER, kTrayMonitorTimer, 0, &result) || !channel.ShouldShowFirstFrame() ||
            shell.events.size() != 1 || std::get<std::string>(shell.events.back().at(V("type"))) != "trayLost") return 16;
        channel.OnMessage(WM_TIMER, kTrayMonitorTimer, 0, &result);
        if (shell.events.size() != 1 || std::get<bool>(shell.Call("window.hideToTray", epoch).value)) return 17;
        const auto snapshot = shell.Call("runtime.snapshot", epoch);
        const auto& facts = std::get<M>(snapshot.value);
        if (std::get<bool>(facts.at(V("trayAvailable"))) ||
            std::get<std::string>(facts.at(V("windowState"))) != "visible") return 18;
        available = true;
        if (!std::get<bool>(shell.Call("tray.retry", epoch).value)) return 19;
        channel.OnMessage(WM_CLOSE, 0, 0, &result);
        if (channel.ShouldShowFirstFrame()) return 20;
        available = false;
        channel.OnMessage(WM_CLOSE, 0, 0, &result);
        if (!channel.ShouldShowFirstFrame()) return 21;
      }
      if (starts != 1 || stops != 1 || shell.registered) return 22;
      monitored.startTrayMonitor = [](HWND, UINT_PTR, UINT) { return UINT_PTR{0}; };
      int workers = 0;
      monitored.startWorker = [&](std::function<void()>) { ++workers; return std::thread{}; };
      bool failed = false;
      const auto beforeHandles = HandleCount();
      try { PlatformChannel channel(nullptr, &shell, args, monitored); }
      catch (const std::runtime_error&) { failed = true; }
      if (!failed || workers || shell.registered || stops != 1 || HandleCount() != beforeHandles) return 23;
      monitored.startTrayMonitor = [&](HWND, UINT_PTR id, UINT) { ++starts; return id; };
      monitored.startWorker = [](std::function<void()>) -> std::thread { throw std::runtime_error("worker failed"); };
      failed = false;
      try { PlatformChannel channel(nullptr, &shell, args, monitored); }
      catch (const std::runtime_error&) { failed = true; }
      if (!failed || starts != 2 || stops != 2 || shell.registered || HandleCount() != beforeHandles) return 24;
    }
    std::filesystem::remove_all(root);
    return 0;
  } catch (const std::exception& error) { std::cerr << error.what(); return 6; }
}
