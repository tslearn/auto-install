#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)

source ${ROOT}/libs/base.sh

TT=`cat<<EOF
127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4
::1         localhost localhost.localdomain localhost6 localhost6.localdomain6
EOF`

forceWriteRemoteFile 192.168.0.81 root World2019 /root/.ssh/test/config "${TT}"
