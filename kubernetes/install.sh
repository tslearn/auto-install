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

# ${1} directory
# ${2} name
# ${3} ip array string
# ${4} dns array string
function makeSSLAuthorFiles() {
  makeEmptyDirectoryAndEnter ${1}
  cp ${ROOT}/cache/ssl/ca.pem ./
  cp ${ROOT}/cache/ssl/ca-key.pem ./

  local embedString=""
  local index=1
  local ip
  local first="yes"

  for ip in ${3}; do
    if [ "${first}" == "yes" ];then
        first="no"
    else
        embedString=${embedString}$'\n'
    fi

    embedString=${embedString}"IP.${index} = ${ip}"
    ((index+=1))
  done

  index=1
  for dns in ${4}; do
    if [ "${first}" == "yes" ];then
        first="no"
    else
        embedString=${embedString}$'\n'
    fi

    embedString=${embedString}"DNS.${index} = ${dns}"
    ((index+=1))
  done

  if [ "${embedString}" == "" ]; then
    cat > ${2}.cnf <<EOF
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
 CN                     = kube-${2}
[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
EOF
  else
    cat > ${2}.cnf <<EOF
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
 CN                     = kube-${2}
[ v3_req ]
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
subjectAltName = @alt_names
[alt_names]
${embedString}
EOF
  fi

  openssl genrsa -out ${2}-key.pem ${SSL_KEY_BITS}
  openssl req -new -key ${2}-key.pem -out ${2}.csr -config ${2}.cnf
  openssl x509 -req -in ${2}.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ${2}.pem -days ${SSL_EXPIRE_DAYS} -extensions v3_req -extfile ${2}.cnf
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} name // etcd
# ${5} version // v3.1.7
function installBin() {
  local content=`cat<<EOF
PATH=\\\$PATH:"${ROOT_INSTALL_DIR}/${4}/${5}/bin"
EOF`

  copyRemoteDirectory ${1} ${2} ${3} ${ROOT}/cache/${4} ${ROOT_INSTALL_DIR}/${4}
  forceWriteRemoteFile ${1} ${2} ${3} "/etc/profile.d/${4}_bin.sh" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 644 /etc/profile.d/${4}_bin.sh"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
# ${4} deploy node name
function installEtcd() {
  # syn time
  deployNtpdate ${1} ${2} ${3} ${NTP_SERVER}

  # open firewall
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=2379/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=2380/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --reload"

  # install
  installBin ${1} ${2} ${3} "etcd" "${ETCD_VERSION}"

  # copy ssl
  makeSSLAuthorFiles ${ROOT}/tmp etcd "127.0.0.1 ${1}" ""
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/ca.pem ${ROOT_INSTALL_DIR}/ssl/ca.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/etcd.pem ${ROOT_INSTALL_DIR}/ssl/etcd.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/etcd-key.pem ${ROOT_INSTALL_DIR}/ssl/etcd-key.pem
  cd ~ && removeDirectory ${ROOT}/tmp

  # make service
  local content=`cat<<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
ExecStart=${ROOT_INSTALL_DIR}/etcd/${ETCD_VERSION}/bin/etcd \\\\
  --name=${4} \\\\
  --cert-file=${ROOT_INSTALL_DIR}/ssl/etcd.pem \\\\
  --key-file=${ROOT_INSTALL_DIR}/ssl/etcd-key.pem \\\\
  --peer-cert-file=${ROOT_INSTALL_DIR}/ssl/etcd.pem \\\\
  --peer-key-file=${ROOT_INSTALL_DIR}/ssl/etcd-key.pem \\\\
  --trusted-ca-file=${ROOT_INSTALL_DIR}/ssl/ca.pem \\\\
  --peer-trusted-ca-file=${ROOT_INSTALL_DIR}/ssl/ca.pem \\\\
  --initial-advertise-peer-urls=https://${1}:2380 \\\\
  --listen-peer-urls=https://${1}:2380 \\\\
  --listen-client-urls=https://${1}:2379 \\\\
  --advertise-client-urls=https://${1}:2379 \\\\
  --initial-cluster-token=${ETCD_CLUSTER_TOKEN} \\\\
  --initial-cluster=$(getEtcdNodes) \\\\
  --initial-cluster-state=new \\\\
  --data-dir=${ROOT_INSTALL_DIR}/etcd/data
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/etcd.service" "${content}"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function startEtcd() {
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable etcd"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start etcd"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function installDocker() {
  # install
  installBin ${1} ${2} ${3} "docker" "${DOCKER_VERSION}"

  # make service
  local content=`cat<<EOF
[Unit]
Description=Docker Application Container Engine
Documentation=http://docs.docker.io

[Service]
EnvironmentFile=-${FLANNEL_DOCKER_ENV_FILE}
Environment="PATH=${ROOT_INSTALL_DIR}/docker/${DOCKER_VERSION}/bin:/bin:/sbin:/usr/bin:/usr/sbin"
ExecStart=${ROOT_INSTALL_DIR}/docker/${DOCKER_VERSION}/bin/dockerd \\\$DOCKER_NETWORK_OPTIONS --log-level=error
ExecReload=/bin/kill -s HUP \\\$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/docker.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable docker"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start docker"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function installFlannel() {
  # install
  installBin ${1} ${2} ${3} "flannel" "${FLANNEL_VERSION}"

  # copy ssl
  makeSSLAuthorFiles ${ROOT}/tmp flannel "" ""
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/ca.pem ${ROOT_INSTALL_DIR}/ssl/ca.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/flannel.pem ${ROOT_INSTALL_DIR}/ssl/flannel.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/flannel-key.pem ${ROOT_INSTALL_DIR}/ssl/flannel-key.pem
  cd ~ && removeDirectory ${ROOT}/tmp

  # make service
  local content=`cat<<EOF
[Unit]
Description=Flanneld overlay address etcd agent
After=network.target
After=network-online.target
Wants=network-online.target
After=etcd.service
Before=docker.service

[Service]
Type=notify
ExecStart=${ROOT_INSTALL_DIR}/flannel/${FLANNEL_VERSION}/bin/flanneld \\\\
  -etcd-cafile=${ROOT_INSTALL_DIR}/ssl/ca.pem \\\\
  -etcd-certfile=${ROOT_INSTALL_DIR}/ssl/flannel.pem \\\\
  -etcd-keyfile=${ROOT_INSTALL_DIR}/ssl/flannel-key.pem \\\\
  -etcd-endpoints=$(getEtcdEndpoints) \\\\
  -etcd-prefix=${FLANNEL_ETCD_PREFIX}
ExecStartPost=${ROOT_INSTALL_DIR}/flannel/${FLANNEL_VERSION}/bin/mk-docker-opts.sh -k DOCKER_NETWORK_OPTIONS -d ${FLANNEL_DOCKER_ENV_FILE}
Restart=on-failure

[Install]
WantedBy=multi-user.target
RequiredBy=docker.service
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/flannel.service" "${content}"

  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable flannel"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start flannel"
}

# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function installMaster() {
  # syn time
  deployNtpdate ${1} ${2} ${3} ${NTP_SERVER}

  # open firewall
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --zone=public --add-port=6443/tcp --permanent"
  runRemoteCommand ${1} ${2} ${3} "~" "firewall-cmd --reload"

  # install
  installBin ${1} ${2} ${3} "master" "${KUBERNETES_VERSION}"

  # copy ssl
  makeSSLAuthorFiles ${ROOT}/tmp master "127.0.0.1 ${1} ${KUBE_CLUSTER_KUBERNETES_SVC_IP}" "kubernetes kubernetes.default kubernetes.default.svc kubernetes.default.svc.cluster.local"
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/cache/ssl/token.csv ${ROOT_INSTALL_DIR}/ssl/token.csv
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/ca.pem ${ROOT_INSTALL_DIR}/ssl/ca.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/ca-key.pem ${ROOT_INSTALL_DIR}/ssl/ca-key.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/master.pem ${ROOT_INSTALL_DIR}/ssl/master.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/master-key.pem ${ROOT_INSTALL_DIR}/ssl/master-key.pem
  cd ~ && removeDirectory ${ROOT}/tmp

  # make kube-apiserver.service
  local content=`cat<<EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
ExecStart=${ROOT_INSTALL_DIR}/master/${KUBERNETES_VERSION}/bin/kube-apiserver \\
  --admission-control=NamespaceLifecycle,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota \\
  --advertise-address=${1} \\
  --allow-privileged=true \\
  --apiserver-count=1 \\
  --authorization-mode=RBAC \\
  --bind-address=${1} \\
  --enable-swagger-ui=true \\
  --insecure-bind-address=127.0.0.1 \\
  --kubelet-certificate-authority=${ROOT_INSTALL_DIR}/ssl/ca.pem \\
  --etcd-cafile=${ROOT_INSTALL_DIR}/ssl/ca.pem \\
  --etcd-servers=$(getEtcdEndpoints) \\
  --service-account-key-file=${ROOT_INSTALL_DIR}/ssl/ca-key.pem \\
  --service-cluster-ip-range=${KUBE_SERVICE_CIDR} \\
  --service-node-port-range=${KUBE_NODE_PORT_RANGE} \\
  --tls-cert-file=${ROOT_INSTALL_DIR}/ssl/master.pem \\
  --tls-private-key-file=${ROOT_INSTALL_DIR}/ssl/master-key.pem \\
  --client-ca-file=${ROOT_INSTALL_DIR}/ssl/ca.pem \\
  --token-auth-file=${ROOT_INSTALL_DIR}/ssl/token.csv \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/kube-apiserver.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable kube-apiserver"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start kube-apiserver"

  # make kube-controller-manager.service
  local content=`cat<<EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=${ROOT_INSTALL_DIR}/master/${KUBERNETES_VERSION}/bin/kube-controller-manager \\
  --cluster-name=kubernetes \\
  --leader-elect=true \\
  --master=http://127.0.0.1:8080 \\
  --root-ca-file=${ROOT_INSTALL_DIR}/ssl/ca.pem \\
  --service-cluster-ip-range=${KUBE_SERVICE_CIDR} \\
  --pod-eviction-timeout 30s \\
  --service-account-private-key-file=${ROOT_INSTALL_DIR}/ssl/ca-key.pem \\
  --cluster-cidr=${KUBE_CLUSTER_CIDR} \\
  --cluster-signing-cert-file=${ROOT_INSTALL_DIR}/ssl/ca.pem \\
  --cluster-signing-key-file=${ROOT_INSTALL_DIR}/ssl/ca-key.pem \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/kube-controller-manager.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable kube-controller-manager"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start kube-controller-manager"

  # make kube-scheduler.service
  local content=`cat<<EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
ExecStart=${ROOT_INSTALL_DIR}/master/${KUBERNETES_VERSION}/bin/kube-scheduler \\
  --master=http://127.0.0.1:8080 \\
  --leader-elect=true \\
  --logtostderr=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/kube-scheduler.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable kube-scheduler"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start kube-scheduler"

  # write flannel to etcd
  installBin ${1} ${2} ${3} "etcdctl" "${ETCD_VERSION}"

  local flannelCommand=`cat<<EOF
#!/usr/bin/env bash
etcdctl \\\\
  --endpoints=$(getEtcdEndpoints) \\\\
  --ca-file=${ROOT_INSTALL_DIR}/ssl/ca.pem \\\\
  set ${FLANNEL_ETCD_PREFIX}/config '{"Network":"'${KUBE_CLUSTER_CIDR}'", "SubnetLen": 24, "Backend": {"Type": "vxlan"}}'
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "~/flannel2etcd.sh" "${flannelCommand}"
  runRemoteCommand ${1} ${2} ${3} "~" "chmod 755 ~/flannel2etcd.sh"
  runRemoteCommand ${1} ${2} ${3} "~" "bash ~/flannel2etcd.sh"
  runRemoteCommand ${1} ${2} ${3} "~" "rm -rf ~/flannel2etcd.sh"

  # install flannel
  installFlannel ${1} ${2} ${3}
}


# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function addNode() {
  # syn time
  deployNtpdate ${1} ${2} ${3} ${NTP_SERVER}

  # open firewall
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl disable firewalld"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl stop firewalld"

  # install flannel
  installFlannel ${1} ${2} ${3}

  # install docker
  installDocker ${1} ${2} ${3}

  # install node
  installBin ${1} ${2} ${3} "node" "${KUBERNETES_VERSION}"

  # copy ssl
  makeSSLAuthorFiles ${ROOT}/tmp node "127.0.0.1 ${1} ${KUBE_CLUSTER_KUBERNETES_SVC_IP}" "cluster.local"
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/ca.pem ${ROOT_INSTALL_DIR}/ssl/ca.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/node.pem ${ROOT_INSTALL_DIR}/ssl/node.pem
  copyRemoteFile ${1} ${2} ${3} ${ROOT}/tmp/node-key.pem ${ROOT_INSTALL_DIR}/ssl/node-key.pem
  cd ~ && removeDirectory ${ROOT}/tmp

  # make kubeconfig
  local content=`cat<<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority: ${ROOT_INSTALL_DIR}/ssl/ca.pem
    server: https://${KUBE_MASTER_IP}:6443
  name: kubernetes
contexts:
- context:
    cluster: kubernetes
    user: kubelet
  name: kubelet
current-context: kubelet
users:
- name: kubelet
  user:
    token: ${KUBELET_TOKEN}
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "${ROOT_INSTALL_DIR}/ssl/kubeconfig" "${content}"

  # make kubelet.service
  local content=`cat<<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service
[Service]
ExecStart=${ROOT_INSTALL_DIR}/node/${KUBERNETES_VERSION}/bin/kubelet \\\\
  --address=${1} \\\\
  --hostname-override=${1} \\\\
  --pod-infra-container-image=registry.cn-beijing.aliyuncs.com/install-kubernetes/pod-infrastructure:v3.6.173.0.49-4 \\\\
  --kubeconfig=${ROOT_INSTALL_DIR}/ssl/kubeconfig \\\\
  --allow-privileged=true \\\\
  --cluster-dns=${KUBE_CLUSTER_DNS_SVC_IP} \\\\
  --cluster-domain=cluster.local. \\\\
  --hairpin-mode promiscuous-bridge \\\\
  --serialize-image-pulls=false \\\\
  --tls-cert-file=${ROOT_INSTALL_DIR}/ssl/node.pem \\\\
  --tls-private-key-file=${ROOT_INSTALL_DIR}/ssl/node-key.pem \\\\
  --fail-swap-on=false \\\\
  --logtostderr=true \\\\
  --v=2
Restart=on-failure
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/kubelet.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable kubelet"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start kubelet"

  # make kube-proxy.service
  local content=`cat<<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
[Service]
ExecStart=${ROOT_INSTALL_DIR}/node/${KUBERNETES_VERSION}/bin/kube-proxy \\\\
  --bind-address=${1} \\\\
  --hostname-override=${1} \\\\
  --cluster-cidr=${KUBE_SERVICE_CIDR} \\\\
  --kubeconfig=${ROOT_INSTALL_DIR}/ssl/kubeconfig \\\\
  --logtostderr=true \\\\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF`

  forceWriteRemoteFile ${1} ${2} ${3} "/etc/systemd/system/kube-proxy.service" "${content}"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl daemon-reload"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl enable kube-proxy"
  runRemoteCommand ${1} ${2} ${3} "~" "systemctl start kube-proxy"

  runRemoteCommand ${1} ${2} ${3} "~" "sysctl -w net.ipv4.ip_forward=1"
  runRemoteCommand ${1} ${2} ${3} "~" "echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/81-ipv4-forward.conf"
}

function startInstall() {
  local name
  local ip

  for name in ${ETCD_CLUSTER_NAMES}; do
    ip=`eval echo '$'"ETCD_IP_${name}"`
    echo -n "root@${ip}(${name}) password: "
    stty -echo
    read ETCD_PASSWORD_${name}
    stty echo
    echo ""
  done

  echo -n "root@${KUBE_MASTER_IP}(master) password: "
  stty -echo
  read MASTER_PASSWORD
  stty echo
  echo ""

  for name in ${NODE_CLUSTER_NAMES}; do
    ip=`eval echo '$'"NODE_IP_${name}"`
    echo -n "root@${ip}(${name}) password: "
    stty -echo
    read NODE_PASSWORD_${name}
    stty echo
    echo ""
  done

  ${ROOT}/init-esxi.sh

  for name in ${ETCD_CLUSTER_NAMES}; do
    installEtcd `eval echo '$'"ETCD_IP_${name}"` "root" `eval echo '$'"ETCD_PASSWORD_${name}"` ${name}
  done
  for name in ${ETCD_CLUSTER_NAMES}; do
    startEtcd `eval echo '$'"ETCD_IP_${name}"` "root" `eval echo '$'"ETCD_PASSWORD_${name}"` &
  done
  wait

  sleep 3
  installMaster ${KUBE_MASTER_IP} "root" ${MASTER_PASSWORD}

  sleep 3
  for name in ${NODE_CLUSTER_NAMES}; do
    addNode `eval echo '$'"NODE_IP_${name}"` "root" `eval echo '$'"NODE_PASSWORD_${name}"`
  done
}

startInstall
