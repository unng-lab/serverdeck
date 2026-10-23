FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive container=docker
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus python3 python3-venv python3-apt sudo openssh-server ca-certificates \
    gpgv gnupg curl procps \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.lock /tmp/requirements.lock
RUN python3 -m venv /opt/serverdeck-executor/venv && \
    /opt/serverdeck-executor/venv/bin/pip install --require-hashes -r /tmp/requirements.lock && \
    /opt/serverdeck-executor/venv/bin/pip check && \
    ln -s /opt/serverdeck-executor/venv /opt/serverdeck-ci && rm /tmp/requirements.lock
COPY . /opt/serverdeck-source
# Dedicated fixture account; no password/key is baked into the image. The
# owned parent harness injects an ephemeral password over docker-exec stdin.
RUN useradd --uid 42001 --create-home --shell /bin/bash --groups adm,systemd-journal sdeck && \
    printf 'HostKey /etc/ssh/ssh_host_ed25519_key\nPasswordAuthentication yes\nPermitRootLogin no\nSetEnv PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin\n' \
      > /etc/ssh/sshd_config.d/serverdeck-fixture.conf && \
    printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod 755 /usr/sbin/policy-rc.d
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
