#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh
source ${ROOT}/config.sh

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function initial() {
  useAliyunRepo_Centos7 ${1} ${2} ${3}
  deployNtpdate ${1} ${2} ${3} ${NTP_SERVER}
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function installNginx() {
  initial ${1} ${2} ${3}
  runRemoteCommand ${1} ${2} ${3} "~" "yum install -y nginx"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=80/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=443/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable nginx"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start nginx"

  runRemoteCommand ${1} ${2} ${3} "/usr/share/nginx/html" "rm -rf *"
  runRemoteCommand ${1} ${2} ${3} "/usr/share/nginx/html" "echo '${1}' > index.html"

  runRemoteCommand ${1} ${2} ${3} "~" "yum install net-tools -y"

  local content=`cat<<EOF
case "\\\$1" in
start)
       /sbin/ifconfig lo:0 ${SNS_VIP} netmask 255.255.255.255 broadcast ${SNS_VIP}
       /sbin/route add -host ${SNS_VIP} dev lo:0
       echo "1" >/proc/sys/net/ipv4/conf/lo/arp_ignore
       echo "2" >/proc/sys/net/ipv4/conf/lo/arp_announce
       echo "1" >/proc/sys/net/ipv4/conf/all/arp_ignore
       echo "2" >/proc/sys/net/ipv4/conf/all/arp_announce
       sysctl -p >/dev/null 2>&1
       echo "RealServer Start OK"
       ;;
stop)
       /sbin/ifconfig lo:0 down
       /sbin/route del ${SNS_VIP} >/dev/null 2>&1
       echo "0" >/proc/sys/net/ipv4/conf/lo/arp_ignore
       echo "0" >/proc/sys/net/ipv4/conf/lo/arp_announce
       echo "0" >/proc/sys/net/ipv4/conf/all/arp_ignore
       echo "0" >/proc/sys/net/ipv4/conf/all/arp_announce
       echo "RealServer Stoped"
       ;;
*)
       echo "Usage: \\\$0 {start|stop}"
       exit 1
esac
exit 0
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/etc/init.d/realserver" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 755 /etc/init.d/realserver"
  runRemoteCommand ${1} ${2} ${3} "~" "service realserver start"
}


# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} state :MASTER BACKUP
# ${5} priority : 100 if master , 99 if BACKUP
function installKeepalived() {
  initial ${1} ${2} ${3}
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl disable firewalld"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl stop firewalld"
#  runRemoteCommand ${1} ${2} ${3} "~" "sysctl -w net.ipv4.ip_forward=1"
#  runRemoteCommand ${1} ${2} ${3} "~" "echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/81-ipv4-forward.conf"

  runRemoteCommand ${1} ${2} ${3} "~" "yum install -y keepalived"
  local content=`cat<<EOF
global_defs {
  notification_email {
    tslearn@163.com
  }
  notification_email_from admin@admin.com
  smtp_server 127.0.0.1
  smtp_connect_timeout 30
  router_id LVS_DEVEL
}
vrrp_instance VI_1 {
  state ${4}
  interface ens192
  virtual_router_id 51
  priority ${5}
  advert_int 1
  authentication {
    auth_type PASS
    auth_pass 1111
  }
  virtual_ipaddress {
    ${SNS_VIP}
  }
}
virtual_server ${SNS_VIP} 80 {
  delay_loop 5
  lb_algo wrr
  lb_kind DR
  persistence_timeout 60
  protocol TCP
  real_server 192.168.0.81 80 {
    weight 3
    TCP_CHECK {
      connect_timeout 10
      nb_get_retry 3
      delay_before_retry 3
      connect_port 80
    }
  }
  real_server 192.168.0.82 80 {
    weight 3
    TCP_CHECK {
      connect_timeout 10
      nb_get_retry 3
      delay_before_retry 3
      connect_port 80
    }
  }
}
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/etc/keepalived/keepalived.conf" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "service keepalived start"
}

${ROOT}/init-esxi.sh
installNginx "192.168.0.81" "root" "World2019"
installNginx "192.168.0.82" "root" "World2019"
installKeepalived "192.168.0.71" "root" "World2019"
installKeepalived "192.168.0.72" "root" "World2019"


