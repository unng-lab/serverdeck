#include "flutter_window.h"

#include <optional>
#include <map>
#include <commctrl.h>
#include <windowsx.h>
#include <flutter/standard_method_codec.h>
#include "resource.h"

#include "flutter/generated_plugin_registrant.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  InitializeDesktopChannel();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (!hidden_) this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTray();
  desktop_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  bool power_event = false;
  if (message == WM_POWERBROADCAST) {
    if (wparam == PBT_APMSUSPEND) {
      Power(true); power_event = true;
    } else if (wparam == PBT_APMRESUMEAUTOMATIC) {
      // RESUMESUSPEND only announces later user activity, not another restore.
      Power(false); power_event = true;
    }
  }
  if (message == WM_APP + 31) {
    switch (LOWORD(lparam)) {
      case WM_CONTEXTMENU:
        ShowTrayMenu({GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)});
        break;
      case NIN_SELECT:
      case NIN_KEYSELECT:
      case WM_LBUTTONDBLCLK:
        Notify("open");
        break;
    }
    return 0;
  }
  if (taskbar_created_ != 0 && message == taskbar_created_) {
    tray_ready_ = false;
    if (!CreateTray()) TrayFailed(); else Notify("trayAvailable");
    return 0;
  }
  if (message == WM_CLOSE) { Notify("closeWindow"); return 0; }
  if (message == WM_APP + 32) { Destroy(); return 0; }
  if (message == WM_APP + 33) {
    // Explicit CloseBlocked force choice: whole-process crash semantics.
    ::TerminateProcess(::GetCurrentProcess(), EXIT_FAILURE);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  if (power_event) return TRUE;
  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}


namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
bool Count(const Value* value, int maximum, int* output) {
  if (!value) return false;
  int64_t number = -1;
  if (auto value32 = std::get_if<int32_t>(value)) number = *value32;
  else if (auto value64 = std::get_if<int64_t>(value)) number = *value64;
  if (number < 0 || number > maximum) return false;
  *output = static_cast<int>(number);
  return true;
}
const Value* Field(const Map& map, const char* key) {
  auto entry = map.find(Value(key));
  return entry == map.end() ? nullptr : &entry->second;
}
}

void FlutterWindow::Notify(const char* action) {
  if (desktop_channel_) desktop_channel_->InvokeMethod("action", std::make_unique<Value>(action));
}
void FlutterWindow::Power(bool suspended) {
  pending_power_ = suspended;
  if (!desktop_ready_) return;
  Notify(suspended ? "suspend" : "resume");
  pending_power_.reset();
}
void FlutterWindow::RestoreWindow() {
  hidden_ = false;
  ::ShowWindow(GetHandle(), SW_RESTORE);
  ::SetForegroundWindow(GetHandle());
}
void FlutterWindow::RemoveTray() {
  if (tray_ready_) ::Shell_NotifyIconW(NIM_DELETE, &tray_data_);
  tray_ready_ = false;
}
void FlutterWindow::TrayFailed() {
  RemoveTray();
  RestoreWindow();
  Notify("trayUnavailable");
}
bool FlutterWindow::CreateTray() {
  if (tray_ready_) return CheckTray();
  if (!taskbar_created_) return false;
  tray_data_ = {};
  tray_data_.cbSize = sizeof(tray_data_);
  tray_data_.hWnd = GetHandle();
  tray_data_.uID = 1;
  tray_data_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP | NIF_SHOWTIP;
  tray_data_.uCallbackMessage = WM_APP + 31;
  tray_data_.hIcon = ::LoadIconW(::GetModuleHandle(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
  wcscpy_s(tray_data_.szTip, L"ServerDeck");
  if (!tray_data_.hIcon || !::Shell_NotifyIconW(NIM_ADD, &tray_data_)) return false;
  tray_data_.uVersion = NOTIFYICON_VERSION_4;
  if (!::Shell_NotifyIconW(NIM_SETVERSION, &tray_data_)) {
    ::Shell_NotifyIconW(NIM_DELETE, &tray_data_);
    return false;
  }
  tray_ready_ = true;
  return true;
}
bool FlutterWindow::CheckTray() {
  if (!tray_ready_) return false;
  if (!::Shell_NotifyIconW(NIM_MODIFY, &tray_data_)) { TrayFailed(); return false; }
  return true;
}
void FlutterWindow::ShowTrayMenu(POINT anchor) {
  HMENU menu = ::CreatePopupMenu();
  if (!menu) { TrayFailed(); return; }
  const auto readiness = L"Движок: " + phase_;
  const auto mcp = L"MCP-сессии: " + std::to_wstring(mcp_sessions_);
  bool ok = ::AppendMenuW(menu, MF_STRING, 101, L"Открыть ServerDeck") &&
      ::AppendMenuW(menu, MF_STRING, 102, L"Серверы") &&
      ::AppendMenuW(menu, MF_STRING, 103, L"Настройки") &&
      ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr) &&
      ::AppendMenuW(menu, MF_STRING | MF_DISABLED | MF_GRAYED, 0, readiness.c_str()) &&
      ::AppendMenuW(menu, MF_STRING | MF_DISABLED | MF_GRAYED, 0, mcp.c_str()) &&
      ::AppendMenuW(menu, MF_SEPARATOR, 0, nullptr) &&
      ::AppendMenuW(menu, MF_STRING, 104, L"Выход");
  if (!ok) { ::DestroyMenu(menu); TrayFailed(); return; }
  if (anchor.x == -1 && anchor.y == -1) ::GetCursorPos(&anchor);
  ::SetForegroundWindow(GetHandle());
  const auto command = ::TrackPopupMenuEx(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON,
      anchor.x, anchor.y, GetHandle(), nullptr);
  ::PostMessage(GetHandle(), WM_NULL, 0, 0);
  ::Shell_NotifyIconW(NIM_SETFOCUS, &tray_data_);
  ::DestroyMenu(menu);
  switch (command) {
    case 101: Notify("open"); break;
    case 102: Notify("servers"); break;
    case 103: Notify("settings"); break;
    case 104: Notify("exit"); break;
  }
}
int FlutterWindow::Ask(const wchar_t* instruction, const wchar_t* content,
    const std::vector<std::pair<int, const wchar_t*>>& choices) {
  RestoreWindow();
  std::vector<TASKDIALOG_BUTTON> buttons;
  for (const auto& choice : choices) buttons.push_back({choice.first, choice.second});
  TASKDIALOGCONFIG config{};
  config.cbSize = sizeof(config);
  config.hwndParent = GetHandle();
  config.dwFlags = static_cast<TASKDIALOG_FLAGS>(TDF_ALLOW_DIALOG_CANCELLATION | TDF_POSITION_RELATIVE_TO_WINDOW);
  config.pszWindowTitle = L"ServerDeck";
  config.pszMainInstruction = instruction;
  config.pszContent = content;
  config.pButtons = buttons.data();
  config.cButtons = static_cast<UINT>(buttons.size());
  config.nDefaultButton = choices.back().first;
  int selected = IDCANCEL;
  if (FAILED(::TaskDialogIndirect(&config, &selected, nullptr, nullptr))) return IDCANCEL;
  return selected;
}
void FlutterWindow::InitializeDesktopChannel() {
  taskbar_created_ = ::RegisterWindowMessageW(L"TaskbarCreated");
  desktop_channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      flutter_controller_->engine()->messenger(), "serverdeck/desktop",
      &flutter::StandardMethodCodec::GetInstance());
  desktop_channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "initialize") {
      const bool tray = CreateTray();
      desktop_ready_ = true;
      // Dart subscribes before initialize. Flush before its reply allows the
      // ordinary engine start to observe a power intent received during boot.
      if (pending_power_.has_value()) Power(*pending_power_);
      result->Success(Value(tray)); return;
    }
    if (method == "show") { RestoreWindow(); result->Success(); return; }
    if (method == "hide") {
      const bool can_hide = CheckTray();
      if (can_hide) { hidden_ = true; ::ShowWindow(GetHandle(), SW_HIDE); }
      result->Success(Value(can_hide)); return;
    }
    if (method == "status") {
      const auto* map = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
      const Value* raw_phase = map ? Field(*map, "phase") : nullptr;
      const auto* phase = raw_phase ? std::get_if<std::string>(raw_phase) : nullptr;
      const std::map<std::string, std::wstring> phases = {
        {"starting", L"Запуск"}, {"ready", L"Готов"}, {"failed", L"Недоступен"},
        {"busy", L"Рабочее пространство занято"},
        {"suspending", L"Приостановка"}, {"suspended", L"Приостановлен"},
        {"resuming", L"Восстановление"},
        {"stopping", L"Завершение"}, {"close-blocked", L"Ожидание завершения"},
        {"closed", L"Завершён"}};
      int count = 0;
      if (!map || map->size() != 2 || !phase || !phases.count(*phase) ||
          !Count(Field(*map, "mcpSessions"), 4, &count)) {
        result->Error("VALIDATION"); return;
      }
      phase_ = phases.at(*phase); mcp_sessions_ = count;
      CheckTray(); result->Success(); return;
    }
    if (method == "fallbackClose") {
      result->Success(Value(Ask(L"Трей недоступен", L"Оставить ServerDeck открытым или выйти?",
        {{201, L"Выйти"}, {202, L"Остаться"}}) == 201)); return;
    }
    if (method == "confirmExit") {
      int count = 0;
      const bool known = Count(call.arguments(), 250, &count);
      const auto text = known ? L"Незавершённых заданий: " + std::to_wstring(count) +
          L". Выход не отменяет принятые удалённые задания. Их состояние восстанавливается при следующем запуске." :
          std::wstring(L"Состояние заданий недоступно. Выход не отменяет принятые удалённые задания.");
      result->Success(Value(Ask(L"Выйти из ServerDeck?", text.c_str(),
        {{201, L"Выйти"}, {202, L"Остаться"}}) == 201)); return;
    }
    if (method == "blockedClose") {
      const int choice = Ask(L"Завершение ещё не подтверждено",
        L"Продолжить ожидание либо завершить весь процесс. Принятые удалённые задания не объявляются отменёнными.",
        {{201, L"Продолжить ожидание"}, {202, L"Завершить процесс"}, {203, L"Остаться"}});
      result->Success(Value(choice == 201 ? "wait" : choice == 202 ? "force" : "stay")); return;
    }
    if (method == "finishExit" || method == "forceExit") {
      const UINT message = method == "forceExit" ? WM_APP + 33 : WM_APP + 32;
      if (!::PostMessage(GetHandle(), message, 0, 0)) { result->Error("SERVICE_UNAVAILABLE"); return; }
      result->Success(); return;
    }
    result->NotImplemented();
  });
}
