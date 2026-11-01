#ifndef RUNNER_MCP_STDIO_H_
#define RUNNER_MCP_STDIO_H_

#include <windows.h>
#include <memory>
#include <vector>
#include <string>

namespace flutter { class BinaryMessenger; }

// Same-process byte carrier only. Never creates a domain Host or another app.
class McpStdio {
 public:
  static std::unique_ptr<McpStdio> Capture();
  ~McpStdio();
  void Bind(flutter::BinaryMessenger* messenger);
  void Pump();
  HANDLE wake_event() const;
 private:
  struct State;
  McpStdio();
  std::unique_ptr<State> state_;
};

// Owns only the short-lived connector process. Never returns to the UI branch.
int RunMcpStdio(std::vector<std::string> arguments);

#endif
