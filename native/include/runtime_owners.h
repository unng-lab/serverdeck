#pragma once
#include <memory>

namespace sd {
// Platform callbacks borrow the engine messenger. This lifetime relationship
// applies to normal close, partial construction and abnormal pump return alike.
template <class Engine, class Platform>
struct RuntimeOwners {
  std::unique_ptr<Engine> engine;
  std::unique_ptr<Platform> platform;
  void Reset() noexcept { platform.reset(); engine.reset(); }
  ~RuntimeOwners() { Reset(); }
};
}
