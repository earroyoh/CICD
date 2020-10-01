#!/bin/sh
# Debian/Ubuntu installation

# Repo update
#sudo apt-get update -y

# CNI Calico installation
# Wait for cluster to be in Ready, it can take a while
#echo "Waiting for cluster to be in Ready state..."
#while [ "`kubectl get nodes | tail -1 | awk '{print $2}'`" != "Ready" ]
#do
#  sleep 5
#done
#POD_CIDR="172.30.0.0/16" \
#	sed -i -e "s?192.168.0.0/16?$POD_CIDR?g" calico.yaml
#kubectl apply -f https://docs.projectcalico.org/v3.16/manifests/calico.yaml

# Comment out for a single node cluster to let it schedule pods
kubectl taint nodes --all node-role.kubernetes.io/master-

# Create namespace
export KUBECONFIG=/home/debian/.kube/admin.conf
kubectl apply -k github.com/istio/installer/base
NAMESPACE=`kubectl get namespace | grep istio | awk '{print $1}'`

# Helm installation
#curl -L https://storage.googleapis.com/kubernetes-helm/helm-v2.14.1-linux-amd64.tar.gz | tar zxvf -
#sudo mv linux-amd64/helm /usr/local/bin
#sudo mv linux-amd64/tiller /usr/local/bin
#curl -L https://bit.ly/install-helm | bash

# Helm tiller service account creation
kubectl create serviceaccount tiller --namespace $NAMESPACE
kubectl create serviceaccount helm --namespace $NAMESPACE

# Helm tiller RBAC
cat > tiller-clusterrolebinding.yaml <<EOF
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: tiller-clusterrolebinding
roleRef:
  kind: ClusterRole
  apiGroup: rbac.authorization.k8s.io
  name: cluster-admin
subjects:
  - kind: ServiceAccount
    name: tiller
    namespace: $NAMESPACE
EOF
kubectl create -f tiller-clusterrolebinding.yaml

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

# Tiller installation
EXTERNAL_IP=`ip address show $IFACE | grep "inet " | awk '{print $2}' | awk -F'/' '{print $1}'`
./gen_tiller_cert.sh $NAMESPACE $EXTERNAL_IP
helm init --tiller-tls --tiller-tls-cert ./tiller.crt --tiller-tls-key ./tiller.key --tiller-tls-verify --tls-ca-cert /etc/kubernetes/pki/ca.crt --service-account tiller --tiller-namespace $TILLER_NAMESPACE
cp helm.crt /home/debian/.helm/cert.pem
cp helm.key /home/debian/.helm/key.pem
cp ca.crt /home/debian/.helm/ca.pem
sudo chown debian:debian $HOME/.helm/cert.pem $HOME/.helm/key.pem $HOME/.helm/ca.pem

export TILLER_NAMESPACE=$NAMESPACE

# Wait tiller to be in Running state, it can take a while
echo "Waiting for tiller to be in Running state..."
while [ "`kubectl get -o template pod/$(kubectl get pods -n $NAMESPACE | grep tiller | awk '{print $1}') -n $NAMESPACE --template={{.status.phase}}`" != "Running" ]
do
  sleep 5
done

# Create helm context config
./get_helm_token.sh $NAMESPACE

# Helm istio-ingress chart installation
helm repo update
git clone https://github.com/istio/istio.git -b release-1.6.11-patch
helm install --name istio-ingress istio/manifests/charts/gateways/istio-ingress -f istio/manifests/charts/global.yaml --tiller-namespace $NAMESPACE --namespace $NAMESPACE --tls
helm install --name istio-discovery istio/manifests/charts/istio-control/istio-discovery -f istio/manifests/charts/global.yaml --tiller-namespace $NAMESPACE --namespace $NAMESPACE --tls

# Wait istio-init to complete 
echo "Waiting for istio-init to be in Running state..."
while [ "`kubectl get -o template pod $(kubectl get pods -n $NAMESPACE | grep istio-init | awk '{print $1}') -n $NAMESPACE --template={{.status.phase}}`" != "" ]
do
  sleep 5
done

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
helm template \
    --set kiali.enabled=true \
    --set grafana.enabled=true \
    --set "kiali.dashboard.jaegerURL=http://jaeger-query:16686" \
    --set "kiali.dashboard.grafanaURL=http://grafana:3000" \
    istio/manifests/charts/istiod-remote \
    --name istio --namespace $NAMESPACE > istio.yaml
kubectl apply -f istio.yaml
