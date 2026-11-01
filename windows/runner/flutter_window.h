#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>

#include <memory>
#include <optional>
#include <vector>
#include <utility>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>
#include <shellapi.h>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void InitializeDesktopChannel();
  bool CreateTray();
  bool CheckTray();
  void RemoveTray();
  void RestoreWindow();
  void Notify(const char* action);
  void Power(bool suspended);
  void TrayFailed();
  void ShowTrayMenu(POINT anchor);
  int Ask(const wchar_t* instruction, const wchar_t* content,
          const std::vector<std::pair<int, const wchar_t*>>& buttons);
  NOTIFYICONDATAW tray_data_{};
  bool tray_ready_ = false;
  bool hidden_ = false;
  bool desktop_ready_ = false;
  std::optional<bool> pending_power_;
  UINT taskbar_created_ = 0;
  std::wstring phase_ = L"Запуск";
  int mcp_sessions_ = 0;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> desktop_channel_;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
