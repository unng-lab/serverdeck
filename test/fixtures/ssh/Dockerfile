# Ephemeral localhost SSH fixture ONLY. No application data, production host or NetBird.
FROM python:3.12.12-slim-bookworm@sha256:593bd06efe90efa80dc4eee3948be7c0fde4134606dd40d8dd8dbcade98e669c
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --shell /bin/sh observer \
    && echo 'observer:serverdeck-disposable-fixture-only' | chpasswd \
    && mkdir -p /run/sshd
COPY sshd_config /etc/ssh/sshd_config
COPY start.sh /start.sh
EXPOSE 22
CMD ["sh", "/start.sh"]
