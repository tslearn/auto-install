#!/usr/bin/env bash
readonly ROOT=$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)
source ${ROOT}/../libs/base.sh
source ${ROOT}/config.sh

DOWNLOAD_URL_etcd="https://github.com/coreos/etcd/releases/download/${ETCD_VERSION}/etcd-${ETCD_VERSION}-linux-amd64.tar.gz"
DOWNLOAD_URL_flannel="https://github.com/coreos/flannel/releases/download/${FLANNEL_VERSION}/flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz"
DOWNLOAD_URL_docker="https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"
DOWNLOAD_URL_kubelet="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubelet"
DOWNLOAD_URL_kube_proxy="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-proxy"
DOWNLOAD_URL_kube_apiserver="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-apiserver"
DOWNLOAD_URL_kube_controller_manager="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-controller-manager"
DOWNLOAD_URL_kube_scheduler="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kube-scheduler"
DOWNLOAD_URL_kubectl="https://storage.googleapis.com/kubernetes-release/release/${KUBERNETES_VERSION}/bin/linux/amd64/kubectl"

DOCKER_IMAGE_NAME_Pause="pause-amd64"
DOCKER_IMAGE_VERSION_Pause="3.0"
DOCKER_IMAGE_NAME_KubernetesDashboard="kubernetes-dashboard-amd64"
DOCKER_IMAGE_VERSION_KubernetesDashboard="v1.7.1"
DOCKER_IMAGE_NAME_K8sDns_KubeDns="k8s-dns-kube-dns-amd64"
DOCKER_IMAGE_VERSION_K8sDns_KubeDns="1.14.7"
DOCKER_IMAGE_NAME_K8sDns_Sidecar="k8s-dns-sidecar-amd64"
DOCKER_IMAGE_VERSION_K8sDns_Sidecar="1.14.7"
DOCKER_IMAGE_NAME_K8sDns_DnsmasqNanny="k8s-dns-dnsmasq-nanny-amd64"
DOCKER_IMAGE_VERSION_K8sDns_DnsmasqNanny="1.14.7"
DOCKER_IMAGE_NAME_Heapster="heapster-amd64"
DOCKER_IMAGE_VERSION_Heapster="v1.4.3"
DOCKER_IMAGE_NAME_HeapsterInfluxdb="heapster-influxdb-amd64"
DOCKER_IMAGE_VERSION_HeapsterInfluxdb="v1.3.3"
DOCKER_IMAGE_NAME_HeapsterGrafana="heapster-grafana-amd64"
DOCKER_IMAGE_VERSION_HeapsterGrafana="v4.4.3"

function initCA() {
  if [ ! -d "${ROOT}/cache/ssl" ]; then
    makeEmptyDirectoryAndEnter ${ROOT}/cache/ssl
    cat > ca.cnf <<EOF
[ req ]
 default_bits           = ${SSL_KEY_BITS}
 distinguished_name     = req_distinguished_name
 prompt                 = no
[ req_distinguished_name ]
 C                      = ${SSL_C}
 ST                     = ${SSL_ST}
 L                      = ${SSL_L}
 O                      = ${SSL_O}
 OU                     = ${SSL_OU}
 CN                     = kube-ca
[ v3_ca ]
keyUsage = critical, keyCertSign, cRLSign
basicConstraints = critical, CA:TRUE, pathlen:2
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
    openssl genrsa -out ca-key.pem ${SSL_KEY_BITS}
    openssl req -x509 -new -nodes -config ca.cnf -extensions v3_ca -key ca-key.pem -days ${SSL_EXPIRE_DAYS} -out ca.pem
    removeFile ca.cnf
  fi
}

function initToken() {
  cd "${ROOT}/cache/ssl"
  cat > token.csv <<EOF
${KUBELET_TOKEN},kubelet,kubelet,"cluster-admin,system:masters"
EOF
}

function cacheEtcd() {
  if [ ! -d "${ROOT}/cache/etcd/${ETCD_VERSION}/bin" ]; then
    makeEmptyDirectoryAndEnter ${ROOT}/cache/etcd/data
    makeEmptyDirectoryAndEnter ${ROOT}/cache/etcd/${ETCD_VERSION}/bin
    makeEmptyDirectoryAndEnter ${ROOT}/cache/etcdctl/${ETCD_VERSION}/bin
    makeEmptyDirectoryAndEnter ${ROOT}/tmp
    wget ${DOWNLOAD_URL_etcd}
    tar -xf etcd-${ETCD_VERSION}-linux-amd64.tar.gz
    cp ./etcd-${ETCD_VERSION}-linux-amd64/etcd ${ROOT}/cache/etcd/${ETCD_VERSION}/bin
    cp ./etcd-${ETCD_VERSION}-linux-amd64/etcdctl ${ROOT}/cache/etcdctl/${ETCD_VERSION}/bin
    chmod -R a+x ${ROOT}/cache/etcd/${ETCD_VERSION}/bin
    chmod -R a+x ${ROOT}/cache/etcdctl/${ETCD_VERSION}/bin
    cd ~
    removeDirectory ${ROOT}/tmp
  fi
}

function cacheFlannel() {
    if [ ! -d "${ROOT}/cache/flannel/${FLANNEL_VERSION}/bin" ]; then
    makeEmptyDirectoryAndEnter ${ROOT}/cache/flannel/${FLANNEL_VERSION}/bin
    makeEmptyDirectoryAndEnter ${ROOT}/tmp
    wget ${DOWNLOAD_URL_flannel}
    tar -xf flannel-${FLANNEL_VERSION}-linux-amd64.tar.gz
    cp ./{flanneld,mk-docker-opts.sh} ${ROOT}/cache/flannel/${FLANNEL_VERSION}/bin
    chmod -R a+x ${ROOT}/cache/flannel/${FLANNEL_VERSION}/bin
    cd ~
    removeDirectory ${ROOT}/tmp
  fi
}

function cacheDocker() {
  if [ ! -d "${ROOT}/cache/docker/${DOCKER_VERSION}/bin" ]; then
    makeEmptyDirectoryAndEnter ${ROOT}/cache/docker/${DOCKER_VERSION}/bin
    makeEmptyDirectoryAndEnter ${ROOT}/tmp
    wget ${DOWNLOAD_URL_docker}
    tar -xf docker-${DOCKER_VERSION}.tgz
    cp ./docker/* ${ROOT}/cache/docker/${DOCKER_VERSION}/bin
    chmod -R a+x ${ROOT}/cache/docker/${DOCKER_VERSION}/bin
    cd ~
    removeDirectory ${ROOT}/tmp
  fi
}

function cacheMaster() {
  if [ ! -d "${ROOT}/cache/master/${KUBERNETES_VERSION}/bin" ]; then
    makeEmptyDirectoryAndEnter ${ROOT}/cache/master/${KUBERNETES_VERSION}/bin
    wget ${DOWNLOAD_URL_kube_apiserver}
    wget ${DOWNLOAD_URL_kube_controller_manager}
    wget ${DOWNLOAD_URL_kube_scheduler}
    wget ${DOWNLOAD_URL_kubectl}
    chmod -R a+x ${ROOT}/cache/master/${KUBERNETES_VERSION}/bin
  fi
}

function cacheNode() {
  if [ ! -d "${ROOT}/cache/node/${KUBERNETES_VERSION}/bin" ]; then
    makeEmptyDirectoryAndEnter ${ROOT}/cache/node/${KUBERNETES_VERSION}/bin
    wget ${DOWNLOAD_URL_kubelet}
    wget ${DOWNLOAD_URL_kube_proxy}
    chmod -R a+x ${ROOT}/cache/node/${KUBERNETES_VERSION}/bin
  fi
}

# ${1} image name
# ${2} image version
function cacheGoogleContainerImage() {
  mkdir -p ${ROOT}/cache/images/google_containers
  docker pull gcr.io/google_containers/${1}:${2}
  docker save -o ${ROOT}/cache/images/google_containers/${1}-${2}.tar gcr.io/google_containers/${1}:${2}
}

function cacheGoogleContainers() {
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_Pause}                ${DOCKER_IMAGE_VERSION_Pause}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_KubernetesDashboard}  ${DOCKER_IMAGE_VERSION_KubernetesDashboard}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_K8sDns_KubeDns}       ${DOCKER_IMAGE_VERSION_K8sDns_KubeDns}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_K8sDns_Sidecar}       ${DOCKER_IMAGE_VERSION_K8sDns_Sidecar}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_K8sDns_DnsmasqNanny}  ${DOCKER_IMAGE_VERSION_K8sDns_DnsmasqNanny}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_Heapster}             ${DOCKER_IMAGE_VERSION_Heapster}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_HeapsterInfluxdb}     ${DOCKER_IMAGE_VERSION_HeapsterInfluxdb}
  cacheGoogleContainerImage ${DOCKER_IMAGE_NAME_HeapsterGrafana}      ${DOCKER_IMAGE_VERSION_HeapsterGrafana}
}

#initCA
#initToken
#cacheEtcd
#cacheFlannel
#cacheDocker
#cacheMaster
#cacheNode

cacheGoogleContainers
