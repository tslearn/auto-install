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

function installEtcdCluster() {
  for name in ${ETCD_CLUSTER_NAMES}; do
    installEtcd `eval echo '$'"ETCD_IP_${name}"` "root" "World2019" ${name}
  done

  for name in ${ETCD_CLUSTER_NAMES}; do
    startEtcd `eval echo '$'"ETCD_IP_${name}"` "root" "World2019" &
  done

  wait
}

${ROOT}/init-esxi.sh
installEtcdCluster
