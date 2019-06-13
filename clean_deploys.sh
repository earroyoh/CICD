#!/bin/sh

export NAMESPACE=cicd
export KUBECONFIG=/etc/kubernetes/admin.conf

helm del --purge jupiterhub-cicd --tiller-namespace $NAMESPACE
helm del --purge gitlab-cicd --tiller-namespace $NAMESPACE
#kubectl delete role/tiller-manager -n $NAMESPACE
kubectl delete rolebinding/tiller-clusterrolebinding -n $NAMESPACE
kubectl delete deployment tiller-deploy -n $NAMESPACE
kubectl delete serviceaccount tiller -n $NAMESPACE
#kubectl delete all,secrets,sa,configmaps,deployments,ingresses,clusterroles,clusterrolebindings,virtualservices,destinationrules,customresourcedefinitions --selector=app=istio -n $NAMESPACE
#kubeadm reset
# rm -Rf /var/lib/etcd
