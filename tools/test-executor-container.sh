#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="serverdeck-executor-ci-$(date +%s)-${RANDOM}"
image="${fixture}:test"
cleanup() {
  docker rm -f "$fixture" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker build --pull -f executor/ci/Dockerfile -t "$image" executor
# This harness runs only on a disposable Linux host. No user server or key is used.
docker run -d --name "$fixture" --label serverdeck.fixture=executor-ci \
  --privileged --cgroupns=host \
  --mount type=bind,source=/sys/fs/cgroup,target=/sys/fs/cgroup \
  --tmpfs /run --tmpfs /run/lock "$image" >/dev/null
ready() {
  for _ in $(seq 1 60); do
    if docker exec "$fixture" systemctl is-active multi-user.target >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs --tail 80 "$fixture"
  return 1
}
ready
docker exec "$fixture" sh -eu -c '
  test "$(ps -p 1 -o comm=)" = systemd
  test "$(dpkg --print-architecture)" = amd64
  python3 -c "import sys; assert sys.version_info[:2] == (3, 12); import apt"
  /opt/serverdeck-ci/bin/pip check
  /opt/serverdeck-ci/bin/ansible --version
  systemctl start ssh
  systemctl is-active ssh
  printf fixture-persisted > /var/lib/serverdeck-ci-marker
'
docker restart --time 30 "$fixture" >/dev/null
ready
docker exec "$fixture" sh -eu -c '
  test "$(cat /var/lib/serverdeck-ci-marker)" = fixture-persisted
  systemctl start ssh
  systemctl is-active ssh
'
# A container init restart is deliberately not reported as a host kernel reboot.
printf '%s\n' '{"scope":"executor-prerequisites","systemd":true,"containerRestart":true,"kernelReboot":false,"executorAcceptance":false}'
