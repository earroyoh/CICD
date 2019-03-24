#!/bin/sh

# Kubernetes standalone cluster installation
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
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

# Helm installation
# curl -L https://storage.googleapis.com/kubernetes-helm/helm-v2.13.1-linux-amd64.tar.gz | gtar xvf -
# mv linux-amd64/helm /usr/local/bin
# mv linux-amd64/tiller /usr/local/bin
curl -L https://bit.ly/install-helm | bash
helm init

# Helm gitlab chart installation
helm repo add gitlab https://charts.gitlab.io/
helm repo update
helm upgrade --install gitlab gitlab/gitlab \
  --timeout 600 \
  --set global.hosts.domain=mydomain.com \
  --set global.hosts.externalIP=127.0.0.1 \
  --set certmanager-issuer.email=email@mydomain.com
kubectl get secret k8s-gitlab-initial-root-password -ojsonpath={.data.password} | base64 --decode ; echo

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
helm install jupyterhub/jupyterhub \
	--version=v0.8 \
	--name=jupytercon \
	--namespace=jupytercon \
	-f config.yaml

# Helm knative chart installation
# helm install knative/knative

