#include "maintenance_status.h"
#include <future>

namespace sd::install {
namespace {
constexpr UINT kStage = WM_APP + 41, kClose = WM_APP + 42;
LRESULT CALLBACK Procedure(HWND window, UINT message, WPARAM value, LPARAM detail) {
  if (message == WM_CREATE) {
    const auto text = CreateWindowExW(0, L"STATIC", MaintenanceText(MaintenanceStage::revalidating),
      WS_CHILD | WS_VISIBLE, 20, 22, 480, 48, window, reinterpret_cast<HMENU>(1), GetModuleHandleW(nullptr), nullptr);
    const auto note = CreateWindowExW(0, L"STATIC", L"Программа откроется после завершения. Пользовательские данные сохраняются.",
      WS_CHILD | WS_VISIBLE, 20, 76, 480, 52, window, reinterpret_cast<HMENU>(2), GetModuleHandleW(nullptr), nullptr);
    if (!text || !note) return -1;
    for (const auto control : {text, note}) SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
    return 0;
  }
  if (message == kStage) {
    SetWindowTextW(GetDlgItem(window, 1), MaintenanceText(static_cast<MaintenanceStage>(value)));
    UpdateWindow(window); return TRUE;
  }
  if (message == kClose) { DestroyWindow(window); return 0; }
  if (message == WM_CLOSE) return 0;
  if (message == WM_DESTROY) { PostQuitMessage(0); return 0; }
  return DefWindowProcW(window, message, value, detail);
}
}
MaintenanceStatus::MaintenanceStatus() {
  std::promise<HWND> ready; auto result = ready.get_future();
  thread_ = std::thread([completion = std::move(ready)]() mutable {
    const auto instance = GetModuleHandleW(nullptr);
    WNDCLASSW type{}; type.lpfnWndProc = Procedure; type.hInstance = instance;
    type.hCursor = LoadCursorW(nullptr, IDC_WAIT); type.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    type.lpszClassName = L"ServerDeckMaintenanceStatusV1";
    if (!RegisterClassW(&type) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) { completion.set_value(nullptr); return; }
    const auto window = CreateWindowExW(WS_EX_DLGMODALFRAME, type.lpszClassName, L"ServerDeck — обновление",
      WS_OVERLAPPED | WS_CAPTION, CW_USEDEFAULT, CW_USEDEFAULT, 540, 180, nullptr, nullptr, instance, nullptr);
    if (window) { ShowWindow(window, SW_SHOWNORMAL); UpdateWindow(window); }
    completion.set_value(window); if (!window) return;
    MSG message{}; while (GetMessageW(&message, nullptr, 0, 0) > 0) { TranslateMessage(&message); DispatchMessageW(&message); }
    if (IsWindow(window)) DestroyWindow(window);
  });
  window_ = result.get();
  if (!window_) { thread_.join(); throw updates::Failure("STORAGE_IO"); }
}
MaintenanceStatus::~MaintenanceStatus() {
  if (window_) PostMessageW(window_, kClose, 0, 0);
  if (thread_.joinable()) thread_.join();
}
void MaintenanceStatus::Report(MaintenanceStage stage) {
  MaintenanceText(stage); DWORD_PTR ignored = 0;
  if (!SendMessageTimeoutW(window_, kStage, static_cast<WPARAM>(stage), 0, SMTO_ABORTIFHUNG | SMTO_BLOCK, 3000, &ignored))
    throw updates::Failure("STORAGE_IO");
}
}
