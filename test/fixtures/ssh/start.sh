#!/bin/sh
set -eu
ssh-keygen -q -t ed25519 -N '' -f /tmp/fixture_host_ed25519_key
exec /usr/sbin/sshd -D -e
