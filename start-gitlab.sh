#!/bin/sh
NAMESPACE=istio-system

# Helm gitlab chart installation
helm repo add gitlab https://charts.gitlab.io/
helm repo update

helm install gitlab/gitlab \
  --name $NAMESPACE-gitlab \
  --timeout 600 \
  --set global.hosts.domain=mydomain.com \
  --set global.hosts.externalIP=127.0.0.1 \
  --set certmanager-issuer.email=gitlab@mydomain.com \
  --kubeconfig ~/.kube/admin.conf \
  --tiller-namespace $NAMESPACE \
  --namespace $NAMESPACE
kubectl get secret $NAMESPACE-gitlab-initial-root-password -ojsonpath={.data.password} | base64 --decode ; echo

