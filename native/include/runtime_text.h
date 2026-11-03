#pragma once

namespace sd {
// Sources are UTF-8. Both bootstrap/native fixtures and Flutter host enforce
// /utf-8 instead of interpreting these literals through the build user's ACP.
inline constexpr wchar_t kTrayOpen[] = L"Открыть";
inline constexpr wchar_t kTrayExit[] = L"Выход";
}
