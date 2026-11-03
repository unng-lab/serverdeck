#include "flutter_window.h"

#include <optional>

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project, const ServerDeckHostArgsV1& args)
    : project_(project), args_(args) {}

FlutterWindow::~FlutterWindow() {
  // The channel borrows the engine messenger; release it first even when
  // the message pump exits without WM_DESTROY.
  OnDestroy();
}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  runtime_.engine = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!runtime_.engine->engine() || !runtime_.engine->view()) {
    return false;
  }
  RegisterPlugins(runtime_.engine->engine());
  runtime_.platform = std::make_unique<PlatformChannel>(GetHandle(),
    runtime_.engine->engine()->messenger(), args_);
  SetChildContent(runtime_.engine->view()->GetNativeWindow());

  runtime_.engine->engine()->SetNextFrameCallback([&]() {
    if (runtime_.platform && runtime_.platform->ShouldShowFirstFrame()) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  runtime_.engine->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  runtime_.Reset();
  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  LRESULT platform_result = 0;
  if (runtime_.platform && runtime_.platform->OnMessage(message, wparam, lparam, &platform_result)) {
    return platform_result;
  }
  if (!runtime_.platform && message == WM_CLOSE) return 0;
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (runtime_.engine) {
    std::optional<LRESULT> result =
        runtime_.engine->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      runtime_.engine->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
