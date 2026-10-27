#!/bin/sh
set -eu
chpasswd < /fixture/password
cat /fixture/client.pub /fixture/encrypted.pub > /home/deck/.ssh/authorized_keys
chown -R deck:deck /home/deck/.ssh
chmod 600 /home/deck/.ssh/authorized_keys
cp /fixture/host /run/hostkey
chmod 600 /run/hostkey
cat > /run/sshd_config <<EOF
Port 22
ListenAddress 0.0.0.0
HostKey /run/hostkey
HostKeyAlgorithms ${HOST_ALGORITHM}
PidFile /run/sshd.pid
PasswordAuthentication yes
PubkeyAuthentication yes
KbdInteractiveAuthentication no
UsePAM no
PermitRootLogin no
AllowUsers deck
LogLevel DEBUG3
EOF
exec /usr/sbin/sshd -D -f /run/sshd_config -E /run/auth.log
