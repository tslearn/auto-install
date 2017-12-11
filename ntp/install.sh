#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh
source ${ROOT}/config.sh

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function installNtp() {
  local restrictStrings
  local name
  local network
  local netmask

  for name in ${NTP_SERVICE_NETWORKS}; do
    network=`eval echo '$'"NTP_SERVICE_NETWORK_${name}"`
    netmask=`eval echo '$'"NTP_SERVICE_NETMASK_${name}"`
    restrictStrings=${restrictStrings}$'\n'"restrict ${network} mask ${netmask}"
  done

  runRemoteCommand ${1} ${2} ${3} "~" "timedatectl set-timezone Asia/Shanghai"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --add-service=ntp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --reload"
  runRemoteCommand ${1} ${2} ${3} "~" "yum install -y ntp"

  local content=`cat<<EOF
driftfile /var/lib/ntp/drift
restrict default nomodify notrap nopeer noquery
restrict 127.0.0.1
restrict ::1

${restrictStrings}

server 0.cn.pool.ntp.org iburst
server 1.cn.pool.ntp.org iburst
server 2.cn.pool.ntp.org iburst
server 3.cn.pool.ntp.org iburst

includefile /etc/ntp/crypto/pw
keys /etc/ntp/keys
disable monitor
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/ntp.conf" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 644 /etc/ntp.conf"

  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable ntpd"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start ntpd"
}

echo -n "root@${NTP_IP}(ntp server) password: "
stty -echo
read NTP_PASSWORD
stty echo
echo ""

installNtp ${NTP_IP} "root" ${NTP_PASSWORD}
