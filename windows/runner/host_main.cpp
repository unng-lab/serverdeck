#define SERVERDECK_HOST_EXPORTS
#include "../../native/include/serverdeck_host.h"
#include <flutter/dart_project.h>
#include <filesystem>
#include "flutter_window.h"
#include "../../native/include/security.h"

int WINAPI ServerDeckRunMainV1(const ServerDeckHostArgsV1* args) {
  if (!args || args->structSize != sizeof(ServerDeckHostArgsV1) ||
      args->abiVersion != 1 || args->launchMode != 0 ||
      !args->runtimeDirectory || !args->dataRoot || !args->exePath ||
      !args->ownerEpoch) return 2;
  const HRESULT com = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(com)) return 3;
  int result = 0;
  bool pumping = false;
  try {
    flutter::DartProject project(
        (std::filesystem::path(args->runtimeDirectory) / L"data").wstring());
    project.set_dart_entrypoint_arguments({sd::Utf8(args->ownerEpoch)});
    FlutterWindow window(project, *args);
    if (!window.Create(L"ServerDeck", {10, 10}, {1280, 720})) {
      result = 4;
    } else {
      window.SetQuitOnClose(true);
      // After beginning to process engine/platform callbacks, failure must not
      // authorize bootstrap to start another engine in this process.
      pumping = true;
      MSG message{};
      BOOL status;
      while ((status = GetMessageW(&message, nullptr, 0, 0)) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
      }
      if (status == -1) result = 5;
    }
  } catch (...) { result = pumping ? SD_HOST_RUNTIME_FAILED : SD_HOST_INITIALIZATION_FAILED; }
  CoUninitialize();
  return result;
}
