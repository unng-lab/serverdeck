#include "serverdeck_host.h"
#include "runtime_text.h"
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
int main() {
  ServerDeckHostArgsV1 args{};
  const ServerDeckRunMainV1Fn failingHost = StartupFailure;
  if (ServerDeckClassifyHostResultV1(failingHost(&args)) !=
      ServerDeckHostDisposition::startupFailure) return 1;
  if (ServerDeckClassifyHostResultV1(RuntimeFailure(&args)) !=
      ServerDeckHostDisposition::runtimeFailure) return 2;
  if (ServerDeckClassifyHostResultV1(999) != ServerDeckHostDisposition::runtimeFailure) return 3;
  if (ServerDeckClassifyHostResultV1(SD_HOST_OK) != ServerDeckHostDisposition::clean) return 4;
  return 0;
}
