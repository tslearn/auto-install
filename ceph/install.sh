#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh
source ${ROOT}/config.sh

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
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

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/hosts" ${content}
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} ntp server
function deployNtpdate() {
  runRemoteCommand ${1} ${2} ${3} "timedatectl set-timezone Asia/Shanghai"
  runRemoteCommand ${1} ${2} ${3} "yum install ntpdate -y"
  runRemoteCommand ${1} ${2} ${3} "/sbin/ntpdate ${4}"
  runRemoteCommand ${1} ${2} ${3} "echo '*/20 * * * * /sbin/ntpdate  ${4} >> /var/log/ntpdate.log' > ntpcrontab"
  runRemoteCommand ${1} ${2} ${3} "crontab ntpcrontab"
  runRemoteCommand ${1} ${2} ${3} "rm -f ntpcrontab"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} user name
# ${5} user password
function createUser() {
  runRemoteCommand ${1} ${2} ${3} "useradd -d /home/${4} -m ${4}"
  runRemoteCommand ${1} ${2} ${3} "passwd ${4}" ${5}
  runRemoteCommand ${1} ${2} ${3} "echo '${4} ALL = (root) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/${3}"
  runRemoteCommand ${1} ${2} ${3} "chmod 0440 /etc/sudoers.d/${4}"
  runRemoteCommand ${1} ${2} ${3} "sed -i s'/Defaults requiretty/#Defaults requiretty'/g /etc/sudoers"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} copy ip / hostname
# ${5} copy user
# ${6} copy password
function copySSHId() {
  runRemoteCommand ${1} ${2} ${3} "sudo ssh-keyscan ${4}  >> ~/.ssh/known_hosts"
  runRemoteCommand ${1} ${2} ${3} "ssh-copy-id ${5}@${4}" ${6}
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} remote user
# ${5} remote password
function deploySSHPassport() {
  local monHosts=""
  local osdHosts=""
  local name
  local content

  for name in ${MONITOR_CLUSTER_NAMES}; do
    monHosts=${monHosts}$'\n'"Host ${name}"$'\n'"  Hostname ${name}"$'\n'"  User ${CEPH_USER_NAME}"
  done
  for name in ${OSD_CLUSTER_NAMES}; do
    osdHosts=${osdHosts}$'\n'"Host ${name}"$'\n'"  Hostname ${name}"$'\n'"  User ${CEPH_USER_NAME}"
  done

  content=`cat<<EOF
Host ${ADMIN_HOSTNAME}
  Hostname ${ADMIN_HOSTNAME}
  User ${CEPH_USER_NAME}
Host ${CLIENT_HOSTNAME}
  Hostname ${CLIENT_HOSTNAME}
  User ${CEPH_USER_NAME}
${monHosts}
${osdHosts}
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "~/.ssh/config" ${content}
  runRemoteCommand ${1} ${2} ${3}  "chmod 644 ~/.ssh/config"
  runRemoteCommand ${1} ${2} ${3}  "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"

  for name in ${MONITOR_CLUSTER_NAMES}; do
    copySSHId  ${1} ${2} ${3} ${name} ${4} ${5}
  done
  for name in ${OSD_CLUSTER_NAMES}; do
    copySSHId  ${1} ${2} ${3} ${name} ${4} ${5}
  done
}

function initialCeph() {
  local name
  local ip
  local password
  for name in ${MONITOR_CLUSTER_NAMES}; do
    ip=`eval echo '$'"MONITOR_IP_${name}"`
    password=`eval echo '$'"MONITOR_PASSWORD_${name}"`
    deployEtcHosts ${ip} "root" ${password}
    deployHostname ${ip} "root" ${password} ${name}
    createUser ${ip} "root" ${password} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
    runRemoteCommand ${ip} "root" ${password}  "setenforce 0"
    runRemoteCommand ${ip} "root" ${password}  "firewall-cmd --zone=public --add-service=ceph-mon --permanent"
    deployNtpdate ${ip} "root" ${password} ${NTP_SERVER}
  done

  for name in ${OSD_CLUSTER_NAMES}; do
    ip=`eval echo '$'"OSD_IP_${name}"`
    password=`eval echo '$'"OSD_PASSWORD_${name}"`

    deployEtcHosts ${ip} "root" ${password}
    deployHostname ${ip} "root" ${password} ${name}
    createUser ${ip} "root" ${password} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
    runRemoteCommand ${ip} "root" ${password}  "setenforce 0"
    runRemoteCommand ${ip} "root" ${password}  "firewall-cmd --zone=public --add-service=ceph --permanent"
    deployNtpdate ${ip} "root" ${password} ${NTP_SERVER}
  done

  deployEtcHosts ${ADMIN_IP} "root" ${ADMIN_PASSWORD}
  deployHostname ${ADMIN_IP} "root" ${ADMIN_PASSWORD} ${ADMIN_HOSTNAME}
  createUser ${ADMIN_IP} "root" ${ADMIN_PASSWORD} ${CEPH_USER_NAME} ${CEPH_USER_PASSWORD}
  deployNtpdate ${ADMIN_IP} "root" ${ADMIN_PASSWORD} ${NTP_SERVER}
}

function installCephDeploy() {
  local content
  runRemoteCommand ${ADMIN_IP} "root" ${ADMIN_PASSWORD} "yum install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm"

  content=`cat<<EOF
[ceph-noarch]
name=Ceph noarch packages
baseurl=https://download.ceph.com/rpm-luminous/el7/noarch
enabled=1
gpgcheck=1
type=rpm-md
gpgkey=https://download.ceph.com/keys/release.asc
EOF`

  runRemoteCommand ${ADMIN_IP} "root" ${ADMIN_PASSWORD} "yum install ceph-deploy -y"
}

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
# Start
########################################################
${ROOT}/init-esxi.sh
initialCeph
installCephDeploy
