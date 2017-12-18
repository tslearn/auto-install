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
#!/usr/bin/env bash
/sbin/ifconfig lo:0 ${SNS_VIP} netmask 255.255.255.255 broadcast ${SNS_VIP}
/sbin/route add -host ${SNS_VIP} dev lo:0
echo "1" >/proc/sys/net/ipv4/conf/lo/arp_ignore
echo "2" >/proc/sys/net/ipv4/conf/lo/arp_announce
echo "1" >/proc/sys/net/ipv4/conf/all/arp_ignore
echo "2" >/proc/sys/net/ipv4/conf/all/arp_announce
sysctl -p >/dev/null 2>&1
echo "RealServer Start OK"
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/opt/realserver/start.sh" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 755 /opt/realserver/start.sh"

  local content=`cat<<EOF
#!/usr/bin/env bash
/sbin/ifconfig lo:0 down
/sbin/route del ${SNS_VIP} >/dev/null 2>&1
echo "0" >/proc/sys/net/ipv4/conf/lo/arp_ignore
echo "0" >/proc/sys/net/ipv4/conf/lo/arp_announce
echo "0" >/proc/sys/net/ipv4/conf/all/arp_ignore
echo "0" >/proc/sys/net/ipv4/conf/all/arp_announce
echo "RealServer Stoped"
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/opt/realserver/stop.sh" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 755 /opt/realserver/stop.sh"

  local content=`cat<<EOF
#!/usr/bin/env bash
/opt/realserver/stop.sh
/opt/realserver/start.sh
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/opt/realserver/restart.sh" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 755 /opt/realserver/restart.sh"

  local content=`cat<<EOF
[Unit]
Description=Keepalived vip service
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=/bin/bash /opt/realserver/start.sh
ExecReload=/bin/bash /opt/realserver/restart.sh
Restart=no
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/realserver.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable realserver"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start realserver"
}


# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} state :MASTER BACKUP
# ${5} priority : 100 if master , 99 if BACKUP
function installKeepalived() {
  initial ${1} ${2} ${3}
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=80/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=443/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --reload"

  runRemoteCommand ${1} ${2} ${3} "~" "yum install net-tools -y"
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
  delay_loop 6
  lb_algo wrr
  lb_kind DR
  persistence_timeout 0
  protocol TCP
  real_server 192.168.0.81 80 {
    weight 3
    TCP_CHECK {
      connect_timeout 1
      delay_before_retry 2
      connect_port 80
    }
  }
  real_server 192.168.0.82 80 {
    weight 3
    TCP_CHECK {
      connect_timeout 1
      delay_before_retry 2
      connect_port 80
    }
  }
}
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/etc/keepalived/keepalived.conf" "${content}"

  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable keepalived"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start keepalived"
}

${ROOT}/init-esxi.sh
installNginx "192.168.0.81" "root" "World2019"
installNginx "192.168.0.82" "root" "World2019"
installKeepalived "192.168.0.71" "root" "World2019" "MASTER" "100"
installKeepalived "192.168.0.72" "root" "World2019" "BACKUP" "99"
installKeepalived "192.168.0.73" "root" "World2019" "BACKUP" "98"


