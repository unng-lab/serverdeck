#pragma once
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <atomic>
#include <deque>
#include <thread>
#include <functional>
#include "../../native/include/serverdeck_host.h"
#include "../../native/include/security.h"
#include "../../native/include/mcp_pipe.h"
#include "../../native/include/monitoring_run.h"
#include <shellapi.h>
#include "update_runtime.h"
#include "../../native/include/update_restart.h"

struct PlatformChannelHooks {
  std::function<HANDLE()> createEvent = [] { return CreateEventW(nullptr, TRUE, FALSE, nullptr); };
  std::function<std::thread(std::function<void()>)> startWorker =
    [](std::function<void()> work) { return std::thread(std::move(work)); };
  // Empty registration override means use the real host resource/shell path.
  std::function<bool(HWND)> createTray;
  std::function<bool(HWND)> isTrayAvailable = [](HWND window) {
    NOTIFYICONDATAW icon{};
    icon.cbSize = sizeof(icon); icon.hWnd = window; icon.uID = 1;
    // Flags zero: probe the registered identity without changing its fields.
    return Shell_NotifyIconW(NIM_MODIFY, &icon) != FALSE;
  };
  std::function<UINT_PTR(HWND, UINT_PTR, UINT)> startTrayMonitor =
    [](HWND window, UINT_PTR id, UINT interval) { return SetTimer(window, id, interval, nullptr); };
  std::function<void(HWND, UINT_PTR)> stopTrayMonitor =
    [](HWND window, UINT_PTR id) { KillTimer(window, id); };
  std::function<std::unique_ptr<UpdateRuntime>()> createUpdates;
};
flutter::EncodableMap EncodeUpdateSnapshot(const sd::updates::Snapshot& snapshot);

constexpr UINT kTrayCallback = WM_APP + 41;
constexpr UINT kActivationMessage = WM_APP + 42;
constexpr UINT kMcpMessage = WM_APP + 45;
constexpr UINT_PTR kTrayMonitorTimer = 0x53445452;
constexpr UINT kTrayMonitorIntervalMs = 500;

class PlatformChannel {
 public:
  PlatformChannel(HWND window, flutter::BinaryMessenger* messenger,
                  const ServerDeckHostArgsV1& args, PlatformChannelHooks hooks = {});
  ~PlatformChannel();
  bool OnMessage(UINT message, WPARAM wparam, LPARAM lparam, LRESULT* result);
  bool ShouldShowFirstFrame() const { return !hidden_ && !IsIconic(window_); }
 private:
  void Handle(const flutter::MethodCall<flutter::EncodableValue>& call,
              std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Emit(const std::string& type);
  bool Tray();
  bool CheckTray();
  void StopTrayMonitor();
  void Restore();
  void CloseActivation();
  void ServeActivation();
  flutter::EncodableMap Snapshot() const;
  sd::updates::UpdateService& Updates();
  HWND window_;
  ServerDeckHostArgsV1 args_;
  PlatformChannelHooks hooks_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::deque<flutter::EncodableMap> pending_;
  uint64_t seq_ = 0;
  UINT taskbarCreated_;
  UINT_PTR trayMonitor_ = 0;
  bool ready_ = false, tray_ = false, hidden_ = false, osEnding_ = false;
  bool exitRequested_ = false, activationClosed_ = false;
  sd::updates::RestartIntent restart_;
  std::atomic<bool> stopping_{false};
  std::atomic<uint32_t> activationStatus_{1};
  sd::Handle stopEvent_;
  sd::Handle activationAckEvent_;
  sd::Handle activationIoEvent_;
  std::thread activationThread_;
  std::unique_ptr<sd::mcp::Broker> mcp_;
  sd::monitoring::RunState monitoringRun_;
  bool updatesStopped_ = false;
  std::unique_ptr<UpdateRuntime> updates_;
};
