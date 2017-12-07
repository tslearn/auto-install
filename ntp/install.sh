#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

source ${ROOT}/config.sh

echo -n "root@${NTP_IP}(ntp server) password: "
stty -echo
read NTP_PASSWORD
stty echo
echo ""

function deployNtpConfig() {
  local restrictStrings
  local name
  local network
  local netmask

  for name in ${NTP_SERVICE_NETWORKS}; do
    network=`eval echo '$'"NTP_SERVICE_NETWORK_${name}"`
    netmask=`eval echo '$'"NTP_SERVICE_NETMASK_${name}"`
    restrictStrings=${restrictStrings}$'\n'"restrict ${network} mask ${netmask}"
  done


  mkdir -p ${ROOT}/tmp
  cd ${ROOT}/tmp
cat > ntp.conf <<EOF
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
EOF
  chmod 644 ${ROOT}/tmp/ntp.conf
/usr/bin/expect << EOF
spawn scp ${ROOT}/tmp/ntp.conf root@${1}:/etc/
expect {
  "password:" { send -- "${2}\r"}
}
expect "100%"
EOF
echo
  cd ${ROOT}
  rm -rf ${ROOT}/tmp
}

function installNtp() {
/usr/bin/expect << EOF
set timeout 300
spawn ssh root@${1}
expect {
  "password:" { send "${2}\r"}
  "yes/no" {  send "yes\r"; exp_continue }
}

expect "root@*#"
send -- "timedatectl set-timezone Asia/Shanghai \r"

expect "root@*#"
send -- "firewall-cmd --add-service=ntp --permanent \r"
expect "root@*#"
send -- "firewall-cmd --reload \r"

expect "root@*#"
send -- "yum install -y ntp \r"

expect "root@*#"
send "logout\r"
EOF
echo

  deployNtpConfig ${1} ${2}

/usr/bin/expect << EOF
set timeout 300
spawn ssh root@${1}
expect {
  "password:" { send "${2}\r"}
  "yes/no" {  send "yes\r"; exp_continue }
}

expect "root@*#"
send -- "systemctl enable ntpd   \r"

expect "root@*#"
send -- "systemctl start ntpd   \r"

expect "root@*#"
send "logout\r"
EOF
echo
}

installNtp ${NTP_IP} ${NTP_PASSWORD}

