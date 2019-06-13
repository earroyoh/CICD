#!/bin/sh

export NAMESPACE=cicd
export KUBECONFIG=/etc/kubernetes/admin.conf

helm del --purge jupiterhub-cicd --tiller-namespace $NAMESPACE
helm del --purge gitlab-cicd --tiller-namespace $NAMESPACE
#kubectl delete role/tiller-manager -n $NAMESPACE
kubectl delete rolebinding/tiller-clusterrolebinding -n $NAMESPACE
kubectl delete deployment tiller-deploy -n $NAMESPACE
kubectl delete serviceaccount tiller -n $NAMESPACE
#kubectl delete secrets,sa,configmaps,services,deployments,pods,ingresses,clusterroles,clusterrolebindings,customresourcedefinition,serviceaccounts --selector=namespace=$NAMESPACE
#kubeadm reset
# rm -Rf /var/lib/etcd
