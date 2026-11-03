#include <windows.h>
#include "../../windows/runner/resource.h"

int main() {
  const auto module = GetModuleHandleW(nullptr);
  if (!FindResourceW(module, MAKEINTRESOURCEW(IDI_APP_ICON), RT_GROUP_ICON)) return 1;
  if (!LoadIconW(module, MAKEINTRESOURCEW(IDI_APP_ICON))) return 2;
  const auto smallIcon = static_cast<HICON>(LoadImageW(module, MAKEINTRESOURCEW(IDI_APP_ICON), IMAGE_ICON,
    GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  if (!smallIcon) return 3;
  DestroyIcon(smallIcon);
  return 0;
}
