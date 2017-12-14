#!/usr/bin/env bash

########################################################
#   Input Password
########################################################
set timeout 60;

echo -n "root@192.168.0.2(esxi) password: "
stty -echo
read ESXI_PASSWORD
stty echo
echo ""

ESXI_VMID_SUN01=1
ESXI_VMID_SUN02=2
ESXI_VMID_SUN03=4

ESXI_VMID_EARTH01=5
ESXI_VMID_EARTH02=6
ESXI_VMID_EARTH03=7

ESXI_VMID_MOON01=8
ESXI_VMID_MOON02=11
ESXI_VMID_MOON03=10

/usr/bin/expect << EOF
set timeout 60
spawn ssh root@192.168.0.2
expect {
  "Password:" { send -- "${ESXI_PASSWORD}\r"}
  "(yes/no)?" {
    send -- "yes\r"
    expect "Password:"
    send -- "${ESXI_PASSWORD}\r"
  }
}

expect "root@"
send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_SUN01} 1 0 \r"

expect "root@"
send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_SUN02} 1 0 \r"
#
#expect "root@"
#send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_SUN03} 1 0 \r"
#
expect "root@"
send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_EARTH01} 1 0 \r"

expect "root@"
send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_EARTH02} 1 0 \r"

#expect "root@"
#send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_EARTH03} 1 0 \r"

#expect "root@"
#send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_MOON01} 1 0 \r"
#
#expect "root@"
#send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_MOON02} 1 0 \r"
#
#expect "root@"
#send "vim-cmd vmsvc/snapshot.revert ${ESXI_VMID_MOON03} 1 0 \r"

expect "root@"
send "logout"
EOF
echo

echo "Waiting ..."
sleep 3
