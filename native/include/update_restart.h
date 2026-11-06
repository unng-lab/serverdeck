#pragma once
#include <string>
#include <utility>
namespace sd::updates {
// Per-owner transient intent. Plain exit/session ending revoke it before final exit.
class RestartIntent {
 public:
  template<class Authorize> bool Request(const std::string& version, bool allowed, Authorize authorize) {
    if (!version_.empty()) return version_ == version;
    if (!allowed || !authorize()) return false;
    version_ = version; return true;
  }
  void Cancel() { version_.clear(); }
  bool requested() const { return !version_.empty(); }
 private:
  std::string version_;
};
}
