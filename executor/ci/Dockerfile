FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive container=docker
RUN apt-get update && apt-get install -y --no-install-recommends \
    systemd systemd-sysv dbus python3 python3-venv python3-apt sudo openssh-server ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY requirements.lock /tmp/requirements.lock
RUN python3 -m venv /opt/serverdeck-ci && \
    /opt/serverdeck-ci/bin/pip install --require-hashes -r /tmp/requirements.lock && \
    /opt/serverdeck-ci/bin/pip check && rm /tmp/requirements.lock
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
