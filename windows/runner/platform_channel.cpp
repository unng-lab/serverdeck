#include "platform_channel.h"
#include "../../native/include/security.h"
#include "../../native/include/instance.h"
#include <shellapi.h>
#include <shobjidl.h>
#include <wincrypt.h>
#include <filesystem>
#include <fstream>
#include <stdexcept>
#include "resource.h"
#include "../../native/include/runtime_text.h"
#include "../../native/include/credential_file.h"

using V = flutter::EncodableValue;
using M = flutter::EncodableMap;
namespace {
struct WipeBytes {
  std::vector<uint8_t>& bytes;
  ~WipeBytes() { SecureZeroMemory(bytes.data(), bytes.size()); }
};
struct WipeDpapi {
  DATA_BLOB& blob;
  ~WipeDpapi() {
    if (blob.pbData) { SecureZeroMemory(blob.pbData, blob.cbData); LocalFree(blob.pbData); }
  }
};
bool StoreId(const std::string& id) {
  if (id.size() != 36 || id[14] != '4' || std::string("89ab").find(id[19]) == std::string::npos) return false;
  for (size_t i = 0; i < id.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) { if (id[i] != '-') return false; }
    else if (std::string("0123456789abcdef").find(id[i]) == std::string::npos) return false;
  }
  return true;
}
const V* Field(const M& map, const char* name) {
  const auto it = map.find(V(name)); return it == map.end() ? nullptr : &it->second;
}
std::string Text(const M& map, const char* name) {
  const auto* value = Field(map, name);
  if (!value || !std::holds_alternative<std::string>(*value))
    throw std::invalid_argument("INVALID_ARGUMENT");
  return std::get<std::string>(*value);
}
std::vector<uint8_t> Bytes(const M& map) {
  const auto* value = Field(map, "bytes");
  if (!value || !std::holds_alternative<std::vector<uint8_t>>(*value))
    throw std::invalid_argument("INVALID_ARGUMENT");
  return std::get<std::vector<uint8_t>>(*value);
}
}
M EncodeUpdateSnapshot(const sd::updates::Snapshot& snapshot) {
  const auto integer = [](uint64_t value) -> V {
    if (value > INT64_MAX) throw sd::updates::Failure("RECOVERY_REQUIRED");
    return V(static_cast<int64_t>(value));
  };
  M result{{V("state"), V(snapshot.state)}, {V("currentVersion"), V(snapshot.current.text)},
    {V("enabled"), V(snapshot.preferences.enabled)}, {V("bytes"), integer(snapshot.bytes)}};
  if (!snapshot.code.empty()) result.emplace(V("code"), V(snapshot.code));
  if (snapshot.total) result.emplace(V("total"), integer(*snapshot.total));
  for (const auto& field : {std::make_pair("lastAttempt", snapshot.preferences.lastAttempt),
      std::make_pair("lastSuccess", snapshot.preferences.lastSuccess), std::make_pair("deferredUntil", snapshot.preferences.deferredUntil)})
    if (field.second) result.emplace(V(field.first), integer(*field.second));
  if (!snapshot.preparedVersion.empty()) result.emplace(V("preparedVersion"), V(snapshot.preparedVersion));
  if (!snapshot.preparedCode.empty()) result.emplace(V("preparedCode"), V(snapshot.preparedCode));
  const bool offerRequired = snapshot.state == "available" || snapshot.state == "downloading" || snapshot.state == "verifying" || snapshot.state == "ready";
  if (offerRequired && !snapshot.offer) throw sd::updates::Failure("RECOVERY_REQUIRED");
  if (snapshot.offer) {
    // The service exposes only verified, compatible offers. Source URLs, hashes
    // and filesystem paths never cross this presentation boundary.
    const auto& release = *snapshot.offer;
    result.emplace(V("targetVersion"), V(release.version.text)); result.emplace(V("notes"), V(release.notes));
    result.emplace(V("publishedUTC"), integer(release.published)); result.emplace(V("setupSize"), integer(release.setupSize));
    result.emplace(V("platform"), V(release.platform)); result.emplace(V("bootstrapAbi"), integer(release.bootstrapAbi));
    result.emplace(V("storeFormat"), integer(release.storeFormat)); result.emplace(V("compatibility"), V("compatible"));
    result.emplace(V("compatibilityReason"), V("Выпуск совместим с текущей программой и форматом данных."));
  }
  return result;
}
sd::updates::UpdateService& PlatformChannel::Updates() {
  if (!updates_) {
    auto created = hooks_.createUpdates ? hooks_.createUpdates() : CreateUpdateRuntime(args_, sd::install::Paths::CurrentUser());
    if (!created || !created->service) throw sd::updates::Failure("STORAGE_IO");
    updates_ = std::move(created);
  }
  return *updates_->service;
}
PlatformChannel::PlatformChannel(HWND window, flutter::BinaryMessenger* messenger,
                               const ServerDeckHostArgsV1& args, PlatformChannelHooks hooks)
    : window_(window), args_(args), hooks_(std::move(hooks)),
      taskbarCreated_(RegisterWindowMessageW(L"TaskbarCreated")),
      stopEvent_(hooks_.createEvent()), activationAckEvent_(hooks_.createEvent()),
      activationIoEvent_(hooks_.createEvent()) {
  if (!taskbarCreated_ || !stopEvent_.valid() || !activationAckEvent_.valid() ||
      !activationIoEvent_.valid()) throw std::runtime_error("ACTIVATION_FAILED");
  channel_ = std::make_unique<flutter::MethodChannel<V>>(
    messenger, "serverdeck/platform.v1", &flutter::StandardMethodCodec::GetInstance());
  try {
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      Handle(call, std::move(result));
    });
    tray_ = Tray();
    trayMonitor_ = hooks_.startTrayMonitor(window_, kTrayMonitorTimer, kTrayMonitorIntervalMs);
    if (!trayMonitor_) throw std::runtime_error("TRAY_MONITOR_FAILED");
    activationThread_ = hooks_.startWorker([this] { ServeActivation(); });
  } catch (...) {
    try { StopTrayMonitor(); } catch (...) {}
    try { channel_->SetMethodCallHandler(nullptr); } catch (...) {}
    NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon); icon.hWnd = window_; icon.uID = 1;
    Shell_NotifyIconW(NIM_DELETE, &icon);
    throw;
  }
}
PlatformChannel::~PlatformChannel() {
  if (updates_) { updates_->service->StopAdmission(); updates_->service->Cancel(); updates_->service->Drain(); }
  try { StopTrayMonitor(); } catch (...) {}
  try { CloseActivation(); } catch (...) {}
  try { channel_->SetMethodCallHandler(nullptr); } catch (...) {}
  NOTIFYICONDATAW icon{}; icon.cbSize = sizeof(icon); icon.hWnd = window_; icon.uID = 1;
  Shell_NotifyIconW(NIM_DELETE, &icon);
}
void PlatformChannel::StopTrayMonitor() {
  const auto timer = trayMonitor_;
  trayMonitor_ = 0;
  if (timer) hooks_.stopTrayMonitor(window_, timer);
}
bool PlatformChannel::CheckTray() {
  if (tray_ && !hooks_.isTrayAvailable(window_)) {
    tray_ = false;
    Restore();
    Emit("trayLost");
  }
  return tray_;
}
M PlatformChannel::Snapshot() const {
  return {{V("ownerEpoch"), V(sd::Utf8(args_.ownerEpoch))},
    {V("seq"), V(static_cast<int64_t>(seq_))},
    {V("windowState"), V(hidden_ ? "trayHidden" : IsIconic(window_) ? "minimized" : "visible")},
    {V("trayAvailable"), V(tray_)}, {V("osEnding"), V(osEnding_)},
    {V("exitRequested"), V(exitRequested_)}};
}
void PlatformChannel::Emit(const std::string& type) {
  M event{{V("version"), V(1)}, {V("ownerEpoch"), V(sd::Utf8(args_.ownerEpoch))},
    {V("seq"), V(static_cast<int64_t>(++seq_))}, {V("type"), V(type)}};
  if (ready_) channel_->InvokeMethod("platform.event", std::make_unique<V>(event));
  else {
    // Facts and irreversible latches are retained in Snapshot even on overflow.
    if (!pending_.empty() && (type == "closeRequested" || type == "trayOpen" || type == "activationRequested") &&
        std::get<std::string>(pending_.back().at(V("type"))) == type) pending_.pop_back();
    if (pending_.size() == 32) pending_.pop_front();
    pending_.push_back(std::move(event));
  }
}
void PlatformChannel::Restore() {
  ShowWindow(window_, SW_RESTORE); SetForegroundWindow(window_); hidden_ = false;
}
bool PlatformChannel::Tray() {
  if (hooks_.createTray) {
    tray_ = hooks_.createTray(window_);
    if (!tray_) Restore();
    return tray_;
  }
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon); icon.hWnd = window_; icon.uID = 1;
  icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
  icon.uCallbackMessage = kTrayCallback;
  HMODULE module = nullptr;
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
        GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        reinterpret_cast<LPCWSTR>(&Text), &module)) { Restore(); return tray_ = false; }
  icon.hIcon = LoadIconW(module, MAKEINTRESOURCEW(IDI_APP_ICON));
  if (!icon.hIcon) { Restore(); return tray_ = false; }
  wcscpy_s(icon.szTip, L"ServerDeck");
  // Retry handles both absent and previously registered icons.
  tray_ = Shell_NotifyIconW(NIM_MODIFY, &icon) || Shell_NotifyIconW(NIM_ADD, &icon);
  if (!tray_) Restore();
  return tray_;
}
void PlatformChannel::Handle(const flutter::MethodCall<V>& call,
                            std::unique_ptr<flutter::MethodResult<V>> result) {
  try {
    const auto* args = call.arguments();
    if (!args || !std::holds_alternative<M>(*args)) throw std::invalid_argument("INVALID_ARGUMENT");
    const auto& map = std::get<M>(*args);
    if (Text(map, "ownerEpoch") != sd::Utf8(args_.ownerEpoch)) {
      result->Error("STALE_EPOCH", "Устаревший экземпляр"); return;
    }
    const auto& name = call.method_name();
    if (name.rfind("updates.", 0) == 0) {
      const bool setting = name == "updates.setEnabled", download = name == "updates.download";
      const bool snapshot = name == "updates.snapshot", cancel = name == "updates.cancel";
      const bool stop = name == "updates.stopAdmission", drained = name == "updates.drained";
      if (!setting && !download && !snapshot && !cancel && !stop && !drained && name != "updates.check" && name != "updates.defer")
        throw std::invalid_argument("INVALID_ARGUMENT");
      if (map.size() != (setting || download ? 2u : 1u)) throw std::invalid_argument("INVALID_ARGUMENT");
      std::string version;
      if (download) {
        version = Text(map, "version");
        try { sd::updates::ParseVersion(version); } catch (...) { throw std::invalid_argument("INVALID_ARGUMENT"); }
      }
      const auto* enabled = setting ? Field(map, "enabled") : nullptr;
      if (setting && (!enabled || !std::holds_alternative<bool>(*enabled))) throw std::invalid_argument("INVALID_ARGUMENT");
      if (stop) {
        updatesStopped_ = true; if (updates_) updates_->service->StopAdmission(); result->Success();
      } else if (cancel) {
        if (updates_) updates_->service->Cancel(); result->Success();
      } else if (drained) {
        result->Success(V(!updates_ || updates_->service->TryDrain()));
      } else if (snapshot && (updatesStopped_ || exitRequested_ || activationClosed_ || osEnding_ || activationStatus_ == 2) && !updates_) {
        sd::updates::Snapshot stopped; stopped.current = UpdateBuildVersion(); stopped.state = "failed"; stopped.code = "CANCELLED";
        result->Success(V(EncodeUpdateSnapshot(stopped)));
      } else {
        if (!snapshot && (updatesStopped_ || exitRequested_ || activationClosed_ || osEnding_ || activationStatus_ != 1))
          throw sd::updates::Failure("CANCELLED");
        if (snapshot) result->Success(V(EncodeUpdateSnapshot(Updates().Read())));
        else if (name == "updates.check") result->Success(V(Updates().Check()));
        else if (download) result->Success(V(Updates().Download(version)));
        else if (setting) { Updates().SetEnabled(std::get<bool>(*enabled)); result->Success(); }
        else { Updates().Defer(); result->Success(); }
      }
    } else if (name == "monitoring.beginRun") {
      if (exitRequested_ || activationClosed_ || osEnding_ || map.size() != 1)
        throw std::invalid_argument("INVALID_ARGUMENT");
      const auto root = std::filesystem::path(args_.dataRoot);
      const bool allowed = monitoringRun_.Begin(
        [&] {
          sd::SecureDirectory(root / L"data");
          return sd::monitoring::Read(root);
        },
        [&](const std::string& bytes) { sd::monitoring::Write(root, bytes); });
      result->Success(V(M{{V("autoAllowed"), V(allowed)}}));
    } else if (name == "credential.pickKey") {
      IFileOpenDialog* dialog = nullptr;
      if (FAILED(CoCreateInstance(CLSID_FileOpenDialog, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&dialog))))
        throw std::runtime_error("KEY_PICKER_FAILED");
      const auto releaseDialog = std::unique_ptr<IFileOpenDialog, void(*)(IFileOpenDialog*)>(dialog, [](IFileOpenDialog* p) { p->Release(); });
      DWORD options = 0;
      if (FAILED(dialog->GetOptions(&options)) || FAILED(dialog->SetOptions(options | FOS_FILEMUSTEXIST | FOS_PATHMUSTEXIST | FOS_FORCEFILESYSTEM | FOS_DONTADDTORECENT)) ||
          FAILED(dialog->SetTitle(L"Выберите приватный ключ SSH"))) throw std::runtime_error("KEY_PICKER_FAILED");
      const HRESULT shown = dialog->Show(window_);
      if (shown == HRESULT_FROM_WIN32(ERROR_CANCELLED)) { result->Success(); return; }
      if (FAILED(shown)) throw std::runtime_error("KEY_PICKER_FAILED");
      IShellItem* item = nullptr; if (FAILED(dialog->GetResult(&item))) throw std::runtime_error("KEY_PICKER_FAILED");
      PWSTR selected = nullptr; const HRESULT found = item->GetDisplayName(SIGDN_FILESYSPATH, &selected); item->Release();
      if (FAILED(found)) throw std::runtime_error("KEY_PICKER_FAILED");
      const std::filesystem::path path(selected); CoTaskMemFree(selected);
      sd::Handle file(CreateFileW(sd::ExtendedPath(path).c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr));
      LARGE_INTEGER size{};
      const bool sizeRead = file.valid() && GetFileSizeEx(file.get(), &size);
      const auto admission = sd::AdmitKeyFile(file.valid(), sizeRead, size.QuadPart);
      if (admission == sd::KeyFileAdmission::readFailed) throw std::runtime_error("KEY_READ_FAILED");
      if (admission == sd::KeyFileAdmission::invalidSize) throw std::invalid_argument("INVALID_ARGUMENT");
      std::vector<uint8_t> bytes(static_cast<size_t>(size.QuadPart)); WipeBytes wipe{bytes}; DWORD count = 0;
      if (!ReadFile(file.get(), bytes.data(), static_cast<DWORD>(bytes.size()), &count, nullptr) || count != bytes.size()) throw std::runtime_error("KEY_READ_FAILED");
      result->Success(V(bytes));
    } else if (name.rfind("mcp.", 0) == 0) {
      if (!mcp_) mcp_ = std::make_unique<sd::mcp::Broker>(args_.dataRoot, sd::Utf8(args_.ownerEpoch),
        [window = window_] { PostMessageW(window, kMcpMessage, 0, 0); });
      if (name == "mcp.publishOwner") mcp_->Publish();
      else if (name == "mcp.removeOwner") mcp_->Remove();
      else if (name == "mcp.sendFrame") mcp_->Send(Text(map, "channelId"), Text(map, "frame"));
      else if (name == "mcp.closeChannel") mcp_->Close(Text(map, "channelId"));
      else if (name == "mcp.ackFrame") mcp_->Acknowledge(Text(map, "channelId"));
      else if (name == "mcp.deleteGrantBlob") mcp_->DeleteGrant(Text(map, "clientId"));
      else if (name == "mcp.writeGrantBlob") {
        const auto* raw = Field(map, "protectedSecret"); const auto* version = Field(map, "grantVersion");
        if (!raw || !std::holds_alternative<std::vector<uint8_t>>(*raw) || !version) throw std::invalid_argument("INVALID_ARGUMENT");
        int64_t number = 0;
        if (std::holds_alternative<int64_t>(*version)) number = std::get<int64_t>(*version);
        else if (std::holds_alternative<int32_t>(*version)) number = std::get<int32_t>(*version);
        else throw std::invalid_argument("INVALID_ARGUMENT");
        mcp_->WriteGrant(Text(map, "clientId"), number, std::get<std::vector<uint8_t>>(*raw));
      } else { result->NotImplemented(); return; }
      result->Success();
    } else if (name == "initialize") {
      const auto release = UpdateBuildVersion().text;
      M context{{V("ownerEpoch"), V(sd::Utf8(args_.ownerEpoch))},
        {V("release"), V(release)},
        {V("userSid"), V(sd::Utf8(sd::UserSid()))}, {V("logonSid"), V(sd::Utf8(sd::LogonSid()))},
        {V("exePath"), V(sd::Utf8(args_.exePath))}, {V("dataRoot"), V(sd::Utf8(args_.dataRoot))},
        {V("runtimeRoot"), V(sd::Utf8(args_.runtimeDirectory))}, {V("trayAvailable"), V(tray_)}};
      result->Success(V(context));
    } else if (name == "runtime.snapshot") {
      if (const auto* state = Field(map, "runtimeState")) {
        if (!std::holds_alternative<std::string>(*state)) throw std::invalid_argument("INVALID_ARGUMENT");
        const auto& value = std::get<std::string>(*state);
        if (value == "shuttingDown" || value == "shutdownBlocked" || value == "terminated") {
          activationStatus_ = 2; updatesStopped_ = true; if (updates_) updates_->service->StopAdmission();
        }
        else if (!exitRequested_) activationStatus_ = value == "running" ? 1 : 3;
      }
      result->Success(V(Snapshot()));
      ready_ = true;
      for (const auto& event : pending_) channel_->InvokeMethod("platform.event", std::make_unique<V>(event));
      pending_.clear();
    } else if (name == "window.hideToTray") {
      const bool available = CheckTray();
      if (available) { ShowWindow(window_, SW_HIDE); hidden_ = true; }
      else Restore();
      result->Success(V(available));
    } else if (name == "window.restore") {
      Restore(); result->Success(V(true));
    } else if (name == "tray.retry") {
      const bool available = Tray(); Emit(available ? "trayReady" : "trayLost");
      result->Success(V(available));
    } else if (name == "runtime.closeActivation") {
      CloseActivation(); result->Success();
    } else if (name == "runtime.finishExit") {
      const auto* complete = Field(map, "shutdownComplete");
      if (!complete || !std::holds_alternative<bool>(*complete) || !std::get<bool>(*complete) ||
          !activationClosed_ || !exitRequested_) throw std::invalid_argument("INVALID_ARGUMENT");
      monitoringRun_.Finish([&](const std::string& bytes) {
        sd::monitoring::Write(std::filesystem::path(args_.dataRoot), bytes);
      });
      result->Success();
      PostMessageW(window_, WM_APP + 43, 0, 0);
    } else if (name == "secret.protect" || name == "secret.unprotect") {
      auto input = Bytes(map);
      WipeBytes wipeInput{input};
      auto purpose = Text(map, "purpose");
      const bool protecting = name == "secret.protect";
      const size_t inputLimit = protecting ? 1024 * 1024 : 2 * 1024 * 1024;
      if (input.size() > inputLimit || purpose.empty() || purpose.size() > 128 ||
          purpose.find('\0') != std::string::npos) {
        throw std::invalid_argument("INVALID_ARGUMENT");
      }
      DATA_BLOB data{static_cast<DWORD>(input.size()), input.data()};
      DATA_BLOB entropy{static_cast<DWORD>(purpose.size()), reinterpret_cast<BYTE*>(purpose.data())};
      DATA_BLOB output{};
      WipeDpapi wipeOutput{output};
      const bool ok = protecting ?
        CryptProtectData(&data, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output) :
        CryptUnprotectData(&data, nullptr, &entropy, nullptr, nullptr, CRYPTPROTECT_UI_FORBIDDEN, &output);
      if (!ok) { result->Error("PROTECTION_UNAVAILABLE", "Защита секрета недоступна"); return; }
      const size_t outputLimit = protecting ? 2 * 1024 * 1024 : 1024 * 1024;
      if (output.cbData > outputLimit) {
        result->Error("PROTECTION_UNAVAILABLE", "Защита секрета недоступна"); return;
      }
      std::vector<uint8_t> bytes(output.pbData, output.pbData + output.cbData);
      WipeBytes wipeBytes{bytes};
      result->Success(V(bytes));
    } else if (name == "file.flushAtomic") {
      const auto path = Text(map, "path");
      const auto bytes = Bytes(map);
      if (bytes.size() > 8192) throw std::invalid_argument("INVALID_ARGUMENT");
      const auto root = std::filesystem::path(args_.dataRoot);
      sd::SecureDirectory(root / L"data");
      sd::SecureDirectory(root / L"data/stores");
      const bool publish = path.rfind("data/publish/", 0) == 0;
      const bool flushOnly = path.rfind("data/flush/", 0) == 0;
      if (publish || flushOnly) {
        const auto id = path.substr(publish ? 13 : 11);
        if (!StoreId(id) || (flushOnly && !bytes.empty()))
          throw std::invalid_argument("INVALID_ARGUMENT");
        const auto staging = root / (L"data/staging-" + sd::Wide(id));
        const auto destination = root / L"data/stores" / sd::Wide(id);
        sd::RejectReparse(staging); sd::RejectReparse(destination);
        const bool hasStaging = std::filesystem::exists(staging);
        const bool hasDestination = std::filesystem::exists(destination);
        if (hasStaging == hasDestination || (flushOnly && !hasStaging)) throw std::runtime_error("STORAGE_IO");
        const auto source = hasStaging ? staging : destination;
        for (const auto& entry : std::filesystem::recursive_directory_iterator(source)) {
          sd::RejectReparse(entry.path());
          if (entry.is_regular_file()) sd::FlushFile(entry.path());
        }
        if (publish) {
          if (hasStaging && !MoveFileExW(staging.c_str(), destination.c_str(), MOVEFILE_WRITE_THROUGH))
            throw std::runtime_error("STORAGE_IO");
          sd::AtomicFile(root / L"data/CURRENT.json", bytes);
        }
      } else if (path == "data/CURRENT.json") sd::AtomicFile(root / L"data/CURRENT.json", bytes);
      else throw std::invalid_argument("INVALID_ARGUMENT");
      result->Success();
    } else result->NotImplemented();
  } catch (const std::invalid_argument&) { result->Error("INVALID_ARGUMENT", "Неверный запрос платформы"); }
    catch (const sd::updates::Failure& error) { result->Error(error.what(), "Операция обновления не выполнена"); }
    catch (...) { result->Error("STORAGE_IO", "Операция платформы не выполнена"); }
}
bool PlatformChannel::OnMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result) {
  *result = 0;
  if (message == kMcpMessage) {
    if (mcp_) for (const auto& event : mcp_->TakeEvents()) {
      M payload{{V("version"), V(1)}, {V("ownerEpoch"), V(sd::Utf8(args_.ownerEpoch))},
        {V("seq"), V(static_cast<int64_t>(++seq_))}, {V("type"), V(event.type)},
        {V("channelId"), V(event.channelId)}, {V("frame"), V(event.frame)},
        {V("userSid"), V(event.userSid)}, {V("logonSid"), V(event.logonSid)}};
      if (ready_) channel_->InvokeMethod("platform.event", std::make_unique<V>(payload));
      // MCP is published only after runtime initialization; an unexpected early
      // event is discarded rather than accumulating private frames in pending_.
      else if (!event.channelId.empty()) mcp_->Close(event.channelId);
    }
    return true;
  }
  if (message == WM_TIMER && trayMonitor_ && wparam == trayMonitor_) {
    CheckTray(); return true;
  }
  if (message == WM_CLOSE) {
    if (CheckTray()) { ShowWindow(window_, SW_HIDE); hidden_ = true; }
    else Restore();
    Emit("closeRequested"); return true;
  }
  if (message == taskbarCreated_) {
    tray_ = false;
    // Restore before attempting recovery, including when Dart is unresponsive.
    Restore(); Emit("trayLost");
    if (Tray()) Emit("trayReady");
    return true;
  }
  if (message == kTrayCallback) {
    if (lparam == WM_LBUTTONDBLCLK) { Restore(); Emit("trayOpen"); }
    else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, 1, sd::kTrayOpen); AppendMenuW(menu, MF_STRING, 2, sd::kTrayExit);
      POINT point{}; GetCursorPos(&point); SetForegroundWindow(window_);
      const UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY,
        point.x, point.y, 0, window_, nullptr);
      DestroyMenu(menu); PostMessageW(window_, WM_NULL, 0, 0);
      if (command == 1) { Restore(); Emit("trayOpen"); }
      if (command == 2) {
        exitRequested_ = true; activationStatus_ = 2; Emit("trayExit");
      }
    }
    return true;
  }
  if (message == WM_QUERYENDSESSION) {
    osEnding_ = exitRequested_ = true; activationStatus_ = 2;
    Emit("osSessionEnding"); *result = TRUE; return true;
  }
  if (message == WM_ENDSESSION) {
    // Windows remains authority for forced session termination.
    if (wparam) { osEnding_ = exitRequested_ = true; Emit("osSessionEnding"); }
    return true;
  }
  if (message == kActivationMessage) {
    if (!exitRequested_) { Restore(); Emit("activationRequested"); }
    SetEvent(activationAckEvent_.get());
    return true;
  }
  if (message == WM_APP + 43) { DestroyWindow(window_); return true; }
  return false;
}
void PlatformChannel::CloseActivation() {
  if (activationClosed_) return;
  stopping_ = true;
  SetEvent(stopEvent_.get()); CancelIoEx(args_.activationPipe, nullptr);
  if (activationThread_.joinable()) activationThread_.join();
  DisconnectNamedPipe(args_.activationPipe);
  sd::RejectReparse(std::filesystem::path(args_.dataRoot) / L"owner.json");
  if (!DeleteFileW((std::filesystem::path(args_.dataRoot) / L"owner.json").c_str()) &&
      GetLastError() != ERROR_FILE_NOT_FOUND) throw std::runtime_error("STORAGE_IO");
  activationClosed_ = true;
}
void PlatformChannel::ServeActivation() {
  const HANDLE event = activationIoEvent_.get();
  auto wait = [&](OVERLAPPED& operation, DWORD* transferred) {
    HANDLE handles[]{stopEvent_.get(), event};
    if (WaitForMultipleObjects(2, handles, FALSE, 3000) != WAIT_OBJECT_0 + 1) {
      CancelIoEx(args_.activationPipe, &operation);
      GetOverlappedResult(args_.activationPipe, &operation, transferred, TRUE);
      return false;
    }
    return GetOverlappedResult(args_.activationPipe, &operation, transferred, FALSE) != 0;
  };
  while (!stopping_) {
    OVERLAPPED operation{}; operation.hEvent = event; ResetEvent(event);
    DWORD transferred = 0;
    BOOL connected = ConnectNamedPipe(args_.activationPipe, &operation);
    if (!connected) {
      const DWORD error = GetLastError();
      if (error == ERROR_IO_PENDING) {
        // Idle accept has no deadline; stopEvent always cancels it.
        HANDLE handles[]{stopEvent_.get(), event};
        const auto signal = WaitForMultipleObjects(2, handles, FALSE, INFINITE);
        if (signal != WAIT_OBJECT_0 + 1) {
          CancelIoEx(args_.activationPipe, &operation);
          GetOverlappedResult(args_.activationPipe, &operation, &transferred, TRUE); break;
        }
        connected = GetOverlappedResult(args_.activationPipe, &operation, &transferred, FALSE);
      } else connected = error == ERROR_PIPE_CONNECTED;
    }
    try {
      if (connected && sd::PeerIdentity(args_.activationPipe, false, sd::UserSid(), sd::LogonSid())) {
        sd::ActivationRequest request{};
        operation = {}; operation.hEvent = event; ResetEvent(event);
        BOOL read = ReadFile(args_.activationPipe, &request, sizeof(request), &transferred, &operation);
        if (!read && GetLastError() == ERROR_IO_PENDING) read = wait(operation, &transferred);
        if (read && transferred == sizeof(request) && request.version == 1 &&
            request.epoch[36] == 0 && request.requestId[36] == 0 &&
            std::wstring(request.epoch) == args_.ownerEpoch) {
          if (activationStatus_ != 2) {
            ResetEvent(activationAckEvent_.get());
            PostMessageW(window_, kActivationMessage, 0, 0);
            HANDLE handles[]{stopEvent_.get(), activationAckEvent_.get()};
            if (WaitForMultipleObjects(2, handles, FALSE, 2500) != WAIT_OBJECT_0 + 1) {
              DisconnectNamedPipe(args_.activationPipe); continue;
            }
          }
          const sd::ActivationAck ack{1, activationStatus_.load()};
          operation = {}; operation.hEvent = event; ResetEvent(event);
          BOOL written = WriteFile(args_.activationPipe, &ack, sizeof(ack), &transferred, &operation);
          if (!written && GetLastError() == ERROR_IO_PENDING) wait(operation, &transferred);
        }
      }
    } catch (...) { /* Reject invalid peers without terminating the owner. */ }
    DisconnectNamedPipe(args_.activationPipe);
  }
}
