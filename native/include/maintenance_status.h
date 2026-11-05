#pragma once
#include "installation.h"
#include <thread>

namespace sd::install {
enum class MaintenanceStage { revalidating, applying, recovering };
inline const wchar_t* MaintenanceText(MaintenanceStage stage) {
  switch (stage) {
    case MaintenanceStage::revalidating: return L"Проверяем допустимость подготовленного обновления…";
    case MaintenanceStage::applying: return L"Применяем обновление ServerDeck…";
    case MaintenanceStage::recovering: return L"Проверяем и восстанавливаем полный комплект программы…";
  }
  return L"Обслуживание ServerDeck…";
}
using MaintenanceReporter = std::function<void(MaintenanceStage)>;
// Native presentation before Flutter/database startup. No business ownership,
// cancel/quit action or window-thread network/file work.
class MaintenanceStatus {
 public:
  MaintenanceStatus();
  ~MaintenanceStatus();
  MaintenanceStatus(const MaintenanceStatus&) = delete;
  MaintenanceStatus& operator=(const MaintenanceStatus&) = delete;
  void Report(MaintenanceStage stage);
 private:
  HWND window_ = nullptr;
  std::thread thread_;
};
}
