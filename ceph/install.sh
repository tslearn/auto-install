#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh


# ${1} deploy ip
# ${2} deploy password
function deployEtcHosts() {
  local monHosts=""
  local osdHosts=""
  local name
  local ip

  for name in ${MONITOR_CLUSTER_NAMES}; do
    ip=`eval echo '$'"MONITOR_IP_${name}"`
    monHosts=${monHosts}$'\n'"${ip}       ${name}"
  done
  for name in ${OSD_CLUSTER_NAMES}; do
    ip=`eval echo '$'"OSD_IP_${name}"`
    osdHosts=${osdHosts}$'\n'"${ip}       ${name}"
  done

  local content=`cat<<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
${monHosts}
${osdHosts}

${ADMIN_IP}       ${ADMIN_HOSTNAME}
${CLIENT_IP}       ${CLIENT_HOSTNAME}
EOF`

  forceWriteRemoteFile ${1} "root" ${2} "/etc/hosts" ${content}
}

# ${1} deploy ip
# ${2} deploy password
# ${3} ntp server
function deployNtpdate() {
  runRemoteCommand ${1} "root" ${2} "timedatectl set-timezone Asia/Shanghai"
  runRemoteCommand ${1} "root" ${2} "yum install ntpdate -y"
  runRemoteCommand ${1} "root" ${2} "/sbin/ntpdate ${3}"
  runRemoteCommand ${1} "root" ${2} "echo '*/20 * * * * /sbin/ntpdate  ${3} >> /var/log/ntpdate.log' > ntpcrontab"
  runRemoteCommand ${1} "root" ${2} "crontab ntpcrontab"
  runRemoteCommand ${1} "root" ${2} "rm -f ntpcrontab"
}

# ${1} deploy ip
# ${2} deploy password
# ${3} user name
# ${4} user password
function createCephUser() {
/usr/bin/expect << EOF
set timeout 120
spawn ssh root@${1}
expect {
  "password:" { send "${2}\r"}
  "yes/no" {  send "yes\r"; exp_continue }
}

expect "root@*\]#"
send "useradd -d /home/${3} -m ${3} \r"

expect "root@*\]#"
send "passwd ${3} \r"
expect "?assword:"
send -- "${4}\r"
expect "?assword:"
send -- "${4}\r"

expect "root@*\]#"
send "echo '${3} ALL = (root) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/${3} \r"
expect "root@*\]#"
send "chmod 0440 /etc/sudoers.d/${3} \r"
expect "root@*\]#"
send "sed -i s'/Defaults requiretty/#Defaults requiretty'/g /etc/sudoers \r"

expect "root@*\]#"
send "logout\r"
EOF
echo
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} copy ip / hostname
# ${5} copy user
# ${6} copy password

function copySSHId() {
/usr/bin/expect << EOF
set timeout 120
spawn ssh ${2}@${1}
expect {
  "password:" { send "${3}\r"}
  "yes/no" {  send "yes\r"; exp_continue }
}

expect "*${2}@*\]"
send "sudo ssh-keyscan ${4}  >> ~/.ssh/known_hosts \r"
expect "*${2}@*\]"
send "ssh-copy-id ${5}@${4} \r"
expect "password:"
send "${6}\r"

expect "*${2}@*\]"
send "logout\r"
EOF
echo
}

# ${1} deploy ip
# ${2} deploy password
function deploySSHPassport() {
  local monHosts=""
  local osdHosts=""
  local name
  local content=`cat<<EOF
Host ${ADMIN_HOSTNAME}
  Hostname ${ADMIN_HOSTNAME}
  User ${CEPH_USER_NAME}
Host ${CLIENT_HOSTNAME}
  Hostname ${CLIENT_HOSTNAME}
  User ${CEPH_USER_NAME}
${monHosts}
${osdHosts}
EOF`

  for name in ${MONITOR_CLUSTER_NAMES}; do
    monHosts=${monHosts}$'\n'"Host ${name}"$'\n'"  Hostname ${name}"$'\n'"  User ${CEPH_USER_NAME}"
  done
  for name in ${OSD_CLUSTER_NAMES}; do
    osdHosts=${osdHosts}$'\n'"Host ${name}"$'\n'"  Hostname ${name}"$'\n'"  User ${CEPH_USER_NAME}"
  done

  forceWriteRemoteFile ${1} ${CEPH_USER_NAME} ${2} "~/.ssh/config" ${content}
  runRemoteCommand ${1} ${CEPH_USER_NAME} ${2} "chmod 644 ~/.ssh/config"
  runRemoteCommand ${1} ${CEPH_USER_NAME} ${2} "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"

  for name in ${MONITOR_CLUSTER_NAMES}; do
    copySSHId  ${1} ${CEPH_USER_NAME} ${2} ${name} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
  done
  for name in ${OSD_CLUSTER_NAMES}; do
    copySSHId  ${1} ${CEPH_USER_NAME} ${2} ${name} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
  done

  copySSHId  ${1} ${CEPH_USER_NAME} ${2} ${ADMIN_HOSTNAME} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
  copySSHId  ${1} ${CEPH_USER_NAME} ${2} ${CLIENT_HOSTNAME} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
}


deployNtpdate "192.168.0.81" "World2019" "192.168.0.71"

########################################################
# Input Password
########################################################
ADMIN_PASSWORD="World2019"
CLIENT_PASSWORD="World2019"
MONITOR_PASSWORD_mon01="World2019"
OSD_PASSWORD_osd01="World2019"
OSD_PASSWORD_osd02="World2019"
OSD_PASSWORD_osd03="World2019"

CEPH_USER_PASSWORD="World2019"

#echo -n "root@${ADMIN_IP}(${ADMIN_HOSTNAME}) password: "
#stty -echo
#read ADMIN_PASSWORD
#stty echo
#echo ""
#
#echo -n "root@${CLIENT_IP}(${CLIENT_HOSTNAME}) password: "
#stty -echo
#read CLIENT_PASSWORD
#stty echo
#echo ""
#
#for name in ${MONITOR_CLUSTER_NAMES}; do
#  NODE_IP=`eval echo '$'"MONITOR_IP_${name}"`
#  echo -n "root@${NODE_IP}(${name}) password: "
#  stty -echo
#  read MONITOR_PASSWORD_${name}
#  stty echo
#  echo ""
#done
#
#for name in ${OSD_CLUSTER_NAMES}; do
#  NODE_IP=`eval echo '$'"OSD_IP_${name}"`
#  echo -n "root@${NODE_IP}(${name}) password: "
#  stty -echo
#  read OSD_PASSWORD_${name}
#  stty echo
#  echo ""
#done

########################################################
# Recover VM
########################################################
#${ROOT}/init-esxi.sh


########################################################
# Initial OS
########################################################
#initialOS
#
#deploySSHPassport ${ADMIN_IP} ${CEPH_USER_PASSWORD}
#
#installCephDeploy ${ADMIN_IP} ${ADMIN_PASSWORD}


