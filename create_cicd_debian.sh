#!/bin/sh
# Debian/Ubuntu installation

# Repo update
#apt-get update -y

# docker-ce installation
#curl -fsSL https://get.docker.com -o get-docker.sh
#sh get-docker.sh
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg2 \
    software-properties-common
#curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
#add-apt-repository \
#   "deb [arch=amd64] https://download.docker.com/linux/debian \
#   buster \
#   stable"
#apt-get update -y
#apt-get install -y docker.io docker-ce-cli containerd.io
apt-get install -y docker.io

# Setup docker daemon.
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
mkdir -p /etc/apt/apt.conf.d/docker.service.d

systemctl enable docker
systemctl daemon-reload && systemctl restart docker
usermod -aG docker debian

# Kubernetes standalone cluster installation
apt-get remove -y --allow-change-held-packages kubelet kubeadm kubectl --purge
apt-get update -y && apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update -y
apt-get install -y --allow-change-held-packages kubeadm=1.23.6-00 kubectl=1.23.6-00 kubelet=1.23.6-00
apt-mark hold kubelet kubeadm kubectl
#setenforce 0
cat <<EOF > config_kubeadm.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupdriver:
    systemd
kubeReserved:
    cpu: "100m"
    memory: "2Gi"
    ephemeral-storage: "1Gi"
systemReserved:
    cpu: "500m"
    memory: "1Gi"
    ephemeral-storage: "1Gi"
evictionHard:
    memory.available: "<500Mi"
    nodefs.available: "<10%"
EOF
#sed -i 's#Environment="KUBELET_KUBECONFIG_ARGS=-.*#Environment="KUBELET_KUBECONFIG_ARGS=--kubeconfig=/etc/kubernetes/kubelet.conf --require-kubeconfig=true --config /etc/kubernetes/config_file.yaml"#g' /etc/systemd/system/kubelet.service.d/10-kubeadm.conf
swapoff -a
systemctl enable kubelet && systemctl restart kubelet
sed -i 's#cgroupDriver:.*#"\#cgroupDriver: systemd"#g' /var/lib/kubelet/config.yaml
systemctl restart kubelet

# Uncomment if k8s version doesn't install it
#docker pull coredns/coredns

export NO_PROXY="localhost,127.0.0.1,10.0.0.0/8,192.168.0.0/16,172.17.0.0/16"
kubeadm init --pod-network-cidr=192.168.0.0/16

export KUBECONFIG=/etc/kubernetes/admin.conf
cp /etc/kubernetes/admin.conf /home/debian/.kube/
chown debian:debian /home/debian/.kube/admin.conf
chmod 600 /home/debian/.kube/admin.conf
kubectl -n kube-system get cm kubeadm-config -oyaml > kubeadm-config.yaml
kubeadm token create --print-join-command > kubeadm-join-command

#echo "Waiting a while to let the kube-system containers run..."
#sleep 120

# CNI Calico installation
kubectl apply -f https://docs.projectcalico.org/v3.18/manifests/calico.yaml
IFACE=`ip link | grep "state UP" | awk -F':' '{print $2}' | sed 's/ //g'`
kubectl set env daemonset/calico-node -n kube-system IP_AUTODETECTION_METHOD=interface=$IFACE

# Wait for cluster to be in Ready, it can take a while
echo "\nWaiting for cluster to be in Ready state..."
while [ "`kubectl get nodes | tail -1 | awk '{print $2}'`" != "Ready" ]
do
  sleep 5
done
echo "\n"
kubectl get nodes

# Comment out for a single node cluster to let it schedule pods
kubectl taint nodes --all node-role.kubernetes.io/master-

# Dashboard UI installation
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
#TOKEN=`kubectl -n kube-system describe secret kubernetes-dashboard | grep "token:" | awk '{print $2}'`
#echo "kubernetes-dashboard token: ${TOKEN}"
#kubectl config set-credentials kubernetes-dashboard --token="${TOKEN}"

# kubernetes/ingress-nginx
#git clone https://github.com/kubernetes/ingress-nginx.git
#kubectl apply -f ingress-nginx/deploy/static/mandatory.yaml

# Create namespace
export NAMESPACE=istio-system
kubectl create namespace $NAMESPACE

# Helm installation
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

# Helm service account creation
kubectl create serviceaccount helm --namespace $NAMESPACE

cat > helm-clusterrole.yaml <<EOF
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: helm-clusterrole
rules:
  - apiGroups: [""]
    resources: ["pods/portforward"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["pods"]
    verbs: ["list", "get"]
EOF
kubectl create -f helm-clusterrole.yaml

cat > helm-clusterrolebinding.yaml <<EOF
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: helm-clusterrolebinding
roleRef:
  kind: ClusterRole
  apiGroup: rbac.authorization.k8s.io
  name: helm-clusterrole
subjects:
  - kind: ServiceAccount
    name: helm
    namespace: $NAMESPACE
EOF
kubectl create -f helm-clusterrolebinding.yaml

#IFACE=wlo1
EXTERNAL_IP=`ip address show $IFACE | grep "inet " | awk '{print $2}' | awk -F'/' '{print $1}'`
./gen_tiller_cert.sh $NAMESPACE $EXTERNAL_IP
cp helm.crt /home/debian/.helm/cert.pem
cp helm.key /home/debian/.helm/key.pem
cp ca.crt /home/debian/.helm/ca.pem
sudo chown debian:debian $HOME/.helm/cert.pem $HOME/.helm/key.pem $HOME/.helm/ca.pem

# Create helm context config
./get_helm_token.sh $NAMESPACE

# Helm ingress-nginx chart installation
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
echo "\nDeploying helm ingress-nginx chart..."
helm install ingress-nginx ingress-nginx/ingress-nginx

# Helm cert-manager chart installation
helm repo add jetstack https://charts.jetstack.io
echo "\nDeploying helm cert-manager chart..."
helm install cert-manager jetstack/cert-manager --namespace cert-manager --create-namespace --version v1.3.0

echo ""
helm list -A

# Helm gitlab chart installation
#helm repo add gitlab https://charts.gitlab.io/
#helm repo update
#helm install gitlab/gitlab \
#  --name $NAMESPACE-gitlab \
#  --timeout 600 \
#  --set global.hosts.domain=mydomain.com \
#  --set global.hosts.externalIP=127.0.0.1 \
#  --set certmanager-issuer.email=gitlab@mydomain.com \
#  --kubeconfig config \
#  --tiller-namespace $NAMESPACE \
#  --namespace $NAMESPACE
#  --tls
#kubectl get secret $NAMESPACE-gitlab-initial-root-password -ojsonpath={.data.password} | base64 --decode ; echo

# Helm jupyterhub chart installation
#helm repo add jupyterhub https://jupyterhub.github.io/helm-chart
#helm repo update
#export HUB_COOKIE_SECRET=`openssl rand -hex 32`
#export PROXY_SECRET_TOKEN=`openssl rand -hex 32`
#cat - << EOF > config.yaml
#$NAMESPACE-hub:
#  cookieSecret: $HUB_COOKIE_SECRET
#$NAMESPACE-proxy:
#  secretToken: $PROXY_SECRET_TOKEN
#EOF
#helm install jupyterhub/jupyterhub \
#  --name $NAMESPACE-jupyterhub \
#  --timeout 600 \
#  --kubeconfig config \
#  --namespace $NAMESPACE \
#  --tiller-namespace $NAMESPACE \
#  --version 0.8.0 \
#  --values config.yaml
#  --tls

# Helm knative chart installation
# helm install knative/knative --namespace $NAMESPACE --tls

# Helm jenkins chart installation
# helm repo update
# helm install stable/jenkins --name jenkins --namespace $NAMESPACE --tls

# Helm istio chart installation
#git clone https://github.com/istio/istio.git
#helm install istio/install/kubernetes/helm/istio-init --name istio-init --namespace $NAMESPACE --tls

# Wait istio-init to complete 
#echo "Waiting for istio-init to be in Running state..."
#while [ "`kubectl get -o template pod/$(kubectl get pods -n $NAMESPACE | grep istio-init | awk '{print $1}') -n $NAMESPACE --template={{.status.phase}}`" != "" ]
#do
#  sleep 5
#done

# Create secret for kiali access
#export KIALI_USERNAME=`openssl rand -hex 4 | base64`
#export KIALI_PASSPHRASE=`openssl rand -hex 16 | base64`
#export KIALI_USERNAME=`echo admin | base64`
#export KIALI_PASSPHRASE=`echo admin | base64`
#cat <<EOF | kubectl apply -f -
#apiVersion: v1
#kind: Secret
#metadata:
#  name: kiali
#  namespace: $NAMESPACE
#  labels:
#    app: kiali
#type: Opaque
#data:
#  username: $KIALI_USERNAME
#  passphrase: $KIALI_PASSPHRASE
#EOF
#helm template \
#    --set kiali.enabled=true \
#    --set grafana.enabled=true \
#    --set "kiali.dashboard.jaegerURL=http://jaeger-query:16686" \
#    --set "kiali.dashboard.grafanaURL=http://grafana:3000" \
#    istio/install/kubernetes/helm/istio \
#    --name istio --namespace $NAMESPACE > istio.yaml
#kubectl apply -f istio.yaml
