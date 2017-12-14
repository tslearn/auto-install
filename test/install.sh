#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh

${ROOT}/init-esxi.sh
useAliyunRepo_Centos7 "192.168.0.71" "root" "World2019"
deployNtpdate "192.168.0.71" "root" "World2019" "1.cn.pool.ntp.org"
