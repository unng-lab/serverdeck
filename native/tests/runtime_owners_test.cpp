#include "runtime_owners.h"
#include <stdexcept>
#include <vector>

struct Engine {
  bool& alive;
  std::vector<int>& order;
  Engine(bool& state, std::vector<int>& sequence) : alive(state), order(sequence) { alive = true; }
  ~Engine() { order.push_back(2); alive = false; }
};
struct Platform {
  Engine& engine;
  bool& invalid;
  Platform(Engine& owner, bool& invalidAccess) : engine(owner), invalid(invalidAccess) {}
  ~Platform() {
    // Models unregistering a handler through the borrowed messenger.
    if (!engine.alive) invalid = true;
    engine.order.push_back(1);
  }
};
int main() {
  bool alive = false, invalid = false;
  std::vector<int> order;
  try {
    sd::RuntimeOwners<Engine, Platform> owners;
    owners.engine = std::make_unique<Engine>(alive, order);
    owners.platform = std::make_unique<Platform>(*owners.engine, invalid);
    throw std::runtime_error("Injected message pump failure with live window owners");
  } catch (const std::runtime_error&) {}
  if (alive || invalid || order != std::vector<int>{1,2}) return 1;
  order.clear();
  {
    sd::RuntimeOwners<Engine, Platform> owners;
    owners.engine = std::make_unique<Engine>(alive, order);
    owners.Reset(); owners.Reset();
  }
  return alive || order != std::vector<int>{2} ? 2 : 0;
}
