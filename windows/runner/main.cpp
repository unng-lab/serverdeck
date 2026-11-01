#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"
#include "mcp_stdio.h"

namespace {
bool ValidMcpArguments(const std::vector<std::string>& args) {
  if (args.empty() || args[0] != "--mcp-stdio") return false;
  if (args.size() == 1) return true;
  if (args.size() != 3 || args[1] != "--grant-id") return false;
  const auto& id = args[2];
  if (id.size() != 36 || id[14] != '4' ||
      (id[19] != '8' && id[19] != '9' && id[19] != 'a' && id[19] != 'b'))
    return false;
  for (size_t i = 0; i < id.size(); ++i) {
    if (i == 8 || i == 13 || i == 18 || i == 23) {
      if (id[i] != '-') return false;
    } else if (!(id[i] >= '0' && id[i] <= '9') && !(id[i] >= 'a' && id[i] <= 'f')) {
      return false;
    }
  }
  return true;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Validate before any console, COM, view, plugin, tray or Flutter DLL call.
  auto parsed = GetCommandLineArguments();
  if (!parsed) return EXIT_FAILURE;
  if (!parsed->empty()) {
    if (!ValidMcpArguments(*parsed)) return EXIT_FAILURE;
    return RunMcpStdio(std::move(*parsed));
  }
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(*parsed));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"serverdeck", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
