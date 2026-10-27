FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends openssh-server \
    && useradd --create-home --shell /bin/sh deck \
    && mkdir -p /run/sshd /home/deck/.ssh \
    && chmod 700 /home/deck/.ssh \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
