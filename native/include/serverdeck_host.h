#pragma once
#include <stdint.h>
#include <windows.h>

// Borrowed strings and handles remain valid for the complete RunMain call.
// No allocation, STL object or exception crosses this ABI.
typedef struct ServerDeckHostArgsV1 {
  uint32_t structSize;
  uint32_t abiVersion;
  const wchar_t* runtimeDirectory;
  const wchar_t* dataRoot;
  const wchar_t* exePath;
  const wchar_t* ownerEpoch;
  HANDLE singletonMutex;
  HANDLE activationPipe;
  uint32_t launchMode;
} ServerDeckHostArgsV1;

typedef int(WINAPI* ServerDeckRunMainV1Fn)(const ServerDeckHostArgsV1*);

enum ServerDeckHostResultV1 {
  SD_HOST_OK = 0,
  SD_HOST_INVALID_ARGS = 2,
  SD_HOST_COM_FAILED = 3,
  SD_HOST_WINDOW_FAILED = 4,
  SD_HOST_MESSAGE_LOOP_FAILED = 5,
  SD_HOST_INITIALIZATION_FAILED = 6,
  SD_HOST_RUNTIME_FAILED = 7,
  SD_HOST_UPDATE_RESTART = 8
};

enum class ServerDeckHostDisposition { clean, startupFailure, runtimeFailure, updateRestart };
inline ServerDeckHostDisposition ServerDeckClassifyHostResultV1(int result) {
  switch (result) {
    case SD_HOST_UPDATE_RESTART: return ServerDeckHostDisposition::updateRestart;
    case SD_HOST_OK: return ServerDeckHostDisposition::clean;
    case SD_HOST_INVALID_ARGS: case SD_HOST_COM_FAILED:
    case SD_HOST_WINDOW_FAILED: case SD_HOST_INITIALIZATION_FAILED:
      return ServerDeckHostDisposition::startupFailure;
    default: return ServerDeckHostDisposition::runtimeFailure;
  }
}

// An explicit pump quit leaves the native window alive until scope teardown.
// Disable its normal WM_DESTROY quit before destruction so native retry UI can
// run on this thread without inheriting a second WM_QUIT.
template<class Window>
int ServerDeckFinishHostPumpV1(int status, WPARAM quitCode, Window& window) {
  if (status == -1) return SD_HOST_MESSAGE_LOOP_FAILED;
  if (quitCode == SD_HOST_UPDATE_RESTART) {
    window.SetQuitOnClose(false);
    return SD_HOST_UPDATE_RESTART;
  }
  return SD_HOST_OK;
}

#ifdef SERVERDECK_HOST_EXPORTS
extern "C" __declspec(dllexport) int WINAPI
ServerDeckRunMainV1(const ServerDeckHostArgsV1* args);
#endif
