#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh
source ${ROOT}/config.sh

KUBE_APISERVER="https://${KUBE_MASTER_IP}:6443"

function getEtcdNodes() {
  local first="yes"
  local ret=""
  local name
  local ip

  for name in ${ETCD_CLUSTER_NAMES}; do
    if [ "${first}" == "yes" ];then
        first="no"
    else
        ret=${ret},
    fi

    ip=`eval echo '$'"ETCD_IP_${name}"`
    ret=${ret}${name}=https://${ip}:2380
  done

  echo "${ret}"
}

function getEtcdEndpoints() {
  local first="yes"
  local ret=""
  local name
  local ip

  for name in ${ETCD_CLUSTER_NAMES}; do
    if [ "${first}" == "yes" ];then
        first="no"
    else
        ret=${ret},
    fi

    ip=`eval echo '$'"ETCD_IP_${name}"`
    ret=${ret}https://${ip}:2379
  done

  echo "${ret}"
}




