#!/bin/sh

# docker-ce installation
yum install -y docker-ce
systemctl enable docker-ce
systemctl start docker

# Kubernetes standalone cluster installation
cat << EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
setenforce 0
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet

swapoff -a
kubeadm init
export KUBECONFIG=/etc/kubernetes/admin.conf
kubectl taint nodes --all node-role.kubernetes.io/master-

# CNI Calico installation
kubectl apply -f https://docs.projectcalico.org/v3.6/getting-started/kubernetes/installation/hosted/kubernetes-datastore/calico-networking/1.7/calico.yaml

# Dashboard UI installation
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/aio/deploy/recommended/kubernetes-dashboard.yaml

# Create namespace cicd
export NAMESPACE=cicd
kubectl create namespace $NAMESPACE

# Helm installation
# curl -L https://storage.googleapis.com/kubernetes-helm/helm-v2.13.1-linux-amd64.tar.gz | gtar xvf -
# mv linux-amd64/helm /usr/local/bin
# mv linux-amd64/tiller /usr/local/bin
curl -L https://bit.ly/install-helm | bash
# Helm tiller RBAC
cat - << EOF > rbac-config-tiller.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: tiller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: kube-system
EOF
kubectl apply -f rbac-config-tiller.yaml
# Helm tiller service account creation
kubectl create -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: tiller
EOF
helm init --service-account=tiller
    
# Helm nginx-ingress chart installation
# helm install stable/nginx-ingress

# Helm gitlab chart installation
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  --timeout=600 \
  --set global.hosts.domain=mydomain.com \
  --set global.hosts.externalIP=127.0.0.1 \
  --set certmanager-issuer.email=email@mydomain.com \
  --namespace=$NAMESPACE 
kubectl get secret $NAMESPACE-gitlab-initial-root-password -ojsonpath={.data.password} | base64 --decode ; echo

# Helm jupyterhub chart installation
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
helm repo update
export HUB_COOKIE_SECRET=`openssl rand -hex 32`
export PROXY_SECRET_TOKEN=`openssl rand -hex 32`
cat - << EOF > config.yaml
hub:
  cookieSecret: $HUB_COOKIE_SECRET
proxy:
  secretToken: $PROXY_SECRET_TOKEN
EOF
export RELEASE=jhub
kubectl create namespace jhub
helm upgrade --install $RELEASE jupyterhub/jupyterhub \
  --timeout=600 \
  --namespace jhub  \
  --version=0.8.0 \
  --values config.yaml

# Helm knative chart installation
# helm install knative/knative

# Helm jenkins chart installation
# helm repo update
# helm install --name jenkins --namespace $NAMESPACE stable/jenkins

