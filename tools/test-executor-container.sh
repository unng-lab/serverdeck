#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-core}"
[[ "$#" -le 1 && ( "$mode" == core || "$mode" == prepare-recipes ) ]] || exit 2
fixture_id="$(python3 -c 'import secrets; print(secrets.token_hex(16))')"
[[ "$fixture_id" =~ ^[a-f0-9]{32}$ ]]
fixture="serverdeck-executor-ci-${fixture_id}"
image="${fixture}:test"
container_id=""
image_id=""
cleanup() {
  if [[ -n "$container_id" ]]; then
    [[ "$(docker inspect --format '{{index .Config.Labels "serverdeck.fixtureId"}}' "$container_id")" == "$fixture_id" ]] || return 1
    [[ "$(docker inspect --format '{{.Image}}' "$container_id")" == "$image_id" ]] || return 1
    docker rm -f "$container_id" >/dev/null || return 1
    container_id=""
  fi
  if [[ -n "$image_id" ]]; then
    [[ "$(docker image inspect --format '{{.Id}}' "$image")" == "$image_id" ]] || return 1
    [[ "$(docker image inspect --format '{{index .Config.Labels "serverdeck.fixtureId"}}' "$image")" == "$fixture_id" ]] || return 1
    docker image rm "$image" >/dev/null || return 1
    image_id=""
  fi
}
on_exit() {
  result=$?
  trap - EXIT
  if ! cleanup; then
    printf '%s\n' 'Owned executor fixture cleanup unconfirmed.' >&2
    [[ "$result" -ne 0 ]] || result=1
  fi
  exit "$result"
}
trap on_exit EXIT
docker build --pull --label "serverdeck.fixtureId=$fixture_id" -f executor/ci/Dockerfile -t "$image" executor
image_id="$(docker image inspect --format '{{.Id}}' "$image")"
# This harness runs only on a disposable Linux host. No user server or key is used.
container_id="$(docker create --name "$fixture" --label serverdeck.fixture=executor-ci \
  --label "serverdeck.fixtureId=$fixture_id" \
  --privileged --cgroupns=host \
  --mount type=bind,source=/sys/fs/cgroup,target=/sys/fs/cgroup \
  --tmpfs /run --tmpfs /run/lock "$image")"
[[ "$container_id" =~ ^[a-f0-9]{64}$ ]]
# Retain ownership before start: an OCI/cgroup failure can leave a created
# container behind even when starting it produces no container ID on stdout.
[[ "$(docker inspect --format '{{index .Config.Labels "serverdeck.fixtureId"}}' "$container_id")" == "$fixture_id" ]]
[[ "$(docker inspect --format '{{.Image}}' "$container_id")" == "$image_id" ]]
docker start "$container_id" >/dev/null
ready() {
  for _ in $(seq 1 60); do
    if docker exec "$container_id" systemctl is-active multi-user.target >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs --tail 80 "$container_id"
  return 1
}
ready
if [[ "$mode" == prepare-recipes ]]; then
  # Metadata preparation only: no enrollment, runtime start or application job.
  artifact=".local/recipe-catalog-${fixture_id}"
  [[ ! -L .local && ( ! -e .local || -d .local ) ]]
  mkdir -p .local
  [[ ! -e "$artifact" && ! -L "$artifact" ]]
  mkdir -m 700 "$artifact"
  preparation_proof="$(timeout 240s docker exec --env "SERVERDECK_FIXTURE_ID=$fixture_id" "$container_id" \
    /usr/bin/python3 -I /opt/serverdeck-source/ci/prepare_recipes.py)"
  docker cp "$container_id:/root/serverdeck-recipe-preparation" "$artifact/inputs"
  python3 tools/build-executor-release.py --output "$artifact/executor-release.json"
  cleanup
  trap - EXIT
  printf '%s\n' "$preparation_proof"
  printf 'RECIPE_PREPARATION_ARTIFACT=%s\n' "$artifact"
  exit 0
fi
docker exec "$container_id" sh -eu -c '
  test "$(ps -p 1 -o comm=)" = systemd
  test "$(dpkg --print-architecture)" = amd64
  python3 -c "import sys; assert sys.version_info[:2] == (3, 12); import apt"
  /opt/serverdeck-ci/bin/pip check
  /opt/serverdeck-ci/bin/ansible --version
  systemctl start ssh
  systemctl is-active ssh
  printf fixture-persisted > /var/lib/serverdeck-ci-marker
'
docker restart --time 30 "$container_id" >/dev/null
ready
docker exec "$container_id" sh -eu -c '
  test "$(cat /var/lib/serverdeck-ci-marker)" = fixture-persisted
  systemctl start ssh
  systemctl is-active ssh
'
docker exec --env PYTHONPATH=/opt/serverdeck-source "$container_id" \
  python3 -m unittest discover -s /opt/serverdeck-source/tests -v
core_proof="$(timeout 240s docker exec --env "SERVERDECK_FIXTURE_ID=$fixture_id" "$container_id" \
  python3 -I /opt/serverdeck-source/ci/core.py)"
cleanup
trap - EXIT
# Emit success only after actual owned resource removal succeeds.
printf '%s\n' "$core_proof"
# A container init restart is deliberately not reported as a host kernel reboot.
printf '%s\n' '{"scope":"executor-prerequisites","systemd":true,"containerRestart":true,"kernelReboot":false,"executorAcceptance":false}'
