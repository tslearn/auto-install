#!/usr/bin/env bash

# 版本信息
KUBERNETES_VERSION="v1.8.5"
DOCKER_VERSION="17.09.1-ce"
ETCD_VERSION="v3.1.10"
FLANNEL_VERSION="v0.9.1"

# 时间同步服务器
NTP_SERVER="ntp5.aliyun.com"

# Etcd 集群配置
ETCD_CLUSTER_NAMES="etcd01 etcd02 etcd03"
ETCD_IP_etcd01="192.168.0.71"
ETCD_IP_etcd02="192.168.0.72"
ETCD_IP_etcd03="192.168.0.73"

# Master IP
KUBE_MASTER_IP="192.168.0.81"

# Node 集群配置
WORKER_CLUSTER_NAMES="worker01 worker02 worker03"
WORKER_IP_worker01="192.168.0.91"
WORKER_IP_worker02="192.168.0.92"
WORKER_IP_worker03="192.168.0.93"

# SSL
SSL_EXPIRE_DAYS=10950
SSL_KEY_BITS=512
SSL_C="CN"
SSL_ST="Beijing"
SSL_L="Beijing"
SSL_O="k8s"
SSL_OU="System"

# 整个系统安装目录
ROOT_INSTALL_DIR=/opt/kubernetes

# POD 网段 (Cluster CIDR），部署前路由不可达，**部署后**路由可达(flanneld保证)
KUBE_CLUSTER_CIDR="172.30.0.0/16"

# TLS Bootstrapping 使用的 Token，可以使用命令生成: cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 64 | head -n 1
KUBELET_TOKEN="A9ool0hyrVRMfjFuFFXxxDDsXAcUsV3U2XXwkc7y174wO6WAJyGLmrBOgxN9OnnV"

# 服务端口范围 (NodePort Range)
NODE_PORT_RANGE="8400-9000"

FLANNEL_ETCD_PREFIX="/kubernetes/network/flannel"
FLANNEL_DOCKER_ENV_FILE="/run/flannel/docker"
ETCD_CLUSTER_TOKEN="etcd-cluster-kube"

# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用IP:Port可达
KUBE_SERVICE_CIDR="10.254.0.0/16"
# kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
KUBE_CLUSTER_KUBERNETES_SVC_IP="10.254.0.1"
# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
KUBE_CLUSTER_DNS_SVC_IP="10.254.0.2"
