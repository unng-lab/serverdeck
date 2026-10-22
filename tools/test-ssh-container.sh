#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
fixture="serverdeck-ssh-ci-$(date +%s)-${RANDOM}"
image="${fixture}:test"
private_dir="$(mktemp -d)"
cleanup() {
  docker rm -f "$fixture" >/dev/null 2>&1 || true
  docker image rm "$image" >/dev/null 2>&1 || true
  rm -rf -- "$private_dir"
}
trap cleanup EXIT
chmod 700 "$private_dir"
# Ephemeral local fixture credentials; never print or upload this directory.
password="$(openssl rand -hex 24)"
printf 'deck:%s\n' "$password" > "$private_dir/password"
printf '%s' "$password" > "$private_dir/password-value"
unset password
ssh-keygen -q -t ed25519 -N '' -f "$private_dir/client"
ssh-keygen -q -t ed25519 -a 16 -N 'fixture-passphrase' -f "$private_dir/encrypted"
ssh-keygen -q -t ed25519 -N '' -f "$private_dir/untrusted-client"
docker build --pull -t "$image" packages/serverdeck_locald/test/ssh_fixture
for algorithm in ssh-ed25519 rsa-sha2-256 rsa-sha2-512; do
  rm -f -- "$private_dir/host" "$private_dir/host.pub"
  if [[ "$algorithm" == ssh-ed25519 ]]; then
    ssh-keygen -q -t ed25519 -N '' -f "$private_dir/host"
    format=ssh-ed25519
  else
    ssh-keygen -q -t rsa -b 3072 -N '' -f "$private_dir/host"
    format=ssh-rsa
  fi
  ssh-keygen -lf "$private_dir/host.pub" -E sha256 | awk '{print $2}' > "$private_dir/fingerprint"
  docker run -d --name "$fixture" --label serverdeck.fixture=ssh-ci \
    -p 127.0.0.1::22 -e "HOST_ALGORITHM=$algorithm" \
    --mount "type=bind,source=$private_dir,target=/fixture,readonly" "$image" >/dev/null
  ready=false
  for _ in $(seq 1 50); do
    if docker exec "$fixture" test -f /run/sshd.pid; then ready=true; break; fi
    sleep 0.1
  done
  if [[ "$ready" != true ]]; then printf '%s\n' 'SSH_FIXTURE_NOT_READY'; exit 1; fi
  port="$(docker inspect --format '{{(index (index .NetworkSettings.Ports "22/tcp") 0).HostPort}}' "$fixture")"
  export SERVERDECK_SSH_FIXTURE="$private_dir" SERVERDECK_SSH_CONTAINER="$fixture"
  export SERVERDECK_SSH_PORT="$port" SERVERDECK_SSH_FORMAT="$format"
  (
    cd packages/serverdeck_locald
    dart test test/ssh_transport_container_test.dart --reporter expanded --concurrency 1
  )
  docker rm -f "$fixture" >/dev/null
done
printf '%s\n' '{"scope":"ssh-transport","hostAlgorithms":3,"persistentTrust":false,"serviceAcceptance":false}'
