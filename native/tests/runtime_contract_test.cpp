#include "serverdeck_host.h"
#include "runtime_text.h"
#include "update_restart.h"
#include <string_view>
#include <cstddef>
#include <type_traits>

static_assert(std::is_standard_layout_v<ServerDeckHostArgsV1>);
static_assert(std::is_trivial_v<ServerDeckHostArgsV1>);
static_assert(sizeof(ServerDeckHostArgsV1) == 64);
static_assert(offsetof(ServerDeckHostArgsV1, runtimeDirectory) == 8);
static_assert(offsetof(ServerDeckHostArgsV1, launchMode) == 56);
static_assert(std::wstring_view(sd::kTrayOpen) == L"\u041e\u0442\u043a\u0440\u044b\u0442\u044c",
              "Native tray text must retain its Unicode code points");
static_assert(std::wstring_view(sd::kTrayExit) == L"\u0412\u044b\u0445\u043e\u0434",
              "Native tray text must not depend on the build user's code page");

namespace {
int WINAPI StartupFailure(const ServerDeckHostArgsV1*) { return SD_HOST_WINDOW_FAILED; }
int WINAPI RuntimeFailure(const ServerDeckHostArgsV1*) { return SD_HOST_MESSAGE_LOOP_FAILED; }
}
struct SyntheticWindow {
  bool quitOnClose = true;
  void SetQuitOnClose(bool value) { quitOnClose = value; }
  ~SyntheticWindow() { if (quitOnClose) PostQuitMessage(0); }
};
int main() {
  ServerDeckHostArgsV1 args{};
  const ServerDeckRunMainV1Fn failingHost = StartupFailure;
  if (ServerDeckClassifyHostResultV1(failingHost(&args)) !=
      ServerDeckHostDisposition::startupFailure) return 1;
  if (ServerDeckClassifyHostResultV1(RuntimeFailure(&args)) !=
      ServerDeckHostDisposition::runtimeFailure) return 2;
  if (ServerDeckClassifyHostResultV1(999) != ServerDeckHostDisposition::runtimeFailure) return 3;
  if (ServerDeckClassifyHostResultV1(SD_HOST_OK) != ServerDeckHostDisposition::clean) return 4;
  if (ServerDeckClassifyHostResultV1(SD_HOST_UPDATE_RESTART) != ServerDeckHostDisposition::updateRestart) return 5;
  sd::updates::RestartIntent restart; int authorizations = 0;
  const auto authorize = [&] { ++authorizations; return true; };
  if (restart.Request("0.2.0", false, authorize) || authorizations || restart.requested()) return 6;
  if (restart.Request("0.2.0", true, [] { return false; }) || restart.requested()) return 7;
  if (!restart.Request("0.2.0", true, authorize) || !restart.requested() || authorizations != 1) return 8;
  if (!restart.Request("0.2.0", false, authorize) || authorizations != 1 || restart.Request("0.3.0", false, authorize)) return 9;
  for (const auto* cancellation : {"trayExit", "osSessionEnding"}) {
    (void)cancellation;
    restart.Cancel(); restart.Cancel();
    if (restart.requested() || restart.Request("0.2.0", false, authorize)) return 10;
    if (!restart.Request("0.2.0", true, authorize)) return 11;
  }
  // Exercise the real thread queue with a synthetic native window teardown;
  // no product, engine, visible window, modal dialog or process is launched.
  {
    SyntheticWindow window;
    PostQuitMessage(SD_HOST_UPDATE_RESTART); MSG message{};
    const auto status = GetMessageW(&message, nullptr, 0, 0);
    if (status != 0 || ServerDeckFinishHostPumpV1(status, message.wParam, window) != SD_HOST_UPDATE_RESTART) return 12;
  }
  MSG remaining{};
  if (PeekMessageW(&remaining, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE)) return 13;
  {
    SyntheticWindow ordinary;
    if (ServerDeckFinishHostPumpV1(-1, SD_HOST_UPDATE_RESTART, ordinary) != SD_HOST_MESSAGE_LOOP_FAILED || !ordinary.quitOnClose) return 14;
  }
  if (!PeekMessageW(&remaining, nullptr, WM_QUIT, WM_QUIT, PM_REMOVE) || remaining.wParam != 0) return 15;
  return 0;
}
