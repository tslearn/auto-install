#!/usr/bin/env bash
# ${1} deploy ip
# ${2} deploy user
# ${3} deploy password
function install-addons-dashboard() {
  local content=`cat<<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: dashboard
  namespace: kube-system

---

kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: dashboard
subjects:
  - kind: ServiceAccount
    name: dashboard
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "${ROOT_INSTALL_DIR}/yaml/dashboard/dashboard-rbac.yaml" "${content}"

  local content=`cat<<EOF
apiVersion: v1
kind: Service
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  type: NodePort
  selector:
    k8s-app: kubernetes-dashboard
  ports:
  - port: 80
    targetPort: 9090
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "${ROOT_INSTALL_DIR}/yaml/dashboard/dashboard-service.yaml" "${content}"

  local content=`cat<<EOF
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: kubernetes-dashboard
  namespace: kube-system
  labels:
    k8s-app: kubernetes-dashboard
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      k8s-app: kubernetes-dashboard
  template:
    metadata:
      labels:
        k8s-app: kubernetes-dashboard
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      serviceAccountName: dashboard
      containers:
      - name: kubernetes-dashboard
        image: gcr.io/google_containers/kubernetes-dashboard-amd64:v1.7.1
        resources:
          # keep request = limit to keep this container in guaranteed class
          limits:
            cpu: 100m
            memory: 300Mi
          requests:
            cpu: 100m
            memory: 100Mi
        ports:
        - containerPort: 9090
        livenessProbe:
          httpGet:
            path: /
            port: 9090
          initialDelaySeconds: 30
          timeoutSeconds: 30
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
EOF`
  forceWriteRemoteFile ${1} ${2} ${3} "${ROOT_INSTALL_DIR}/yaml/dashboard/dashboard-controller.yaml" "${content}"

  runRemoteCommand ${1} ${2} ${3} "~" "kubectl create -f ${ROOT_INSTALL_DIR}/yaml/dashboard/"
}
