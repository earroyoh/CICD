#!/bin/sh
export NAMESPACE=cicd

# Find the secret associated with the Service Account
SECRET=$(kubectl -n $NAMESPACE get sa helm -o jsonpath='{.secrets[].name}')

# Retrieve the token from the secret and decode it
TOKEN=$(kubectl get secrets -n $NAMESPACE $SECRET -o jsonpath='{.data.token}' | base64 -D)

# Retrieve the CA from the secret, decode it and write it to disk
kubectl get secrets -n $NAMESPACE $SECRET -o jsonpath='{.data.ca\.crt}' | base64 -D > ca.crt

# Retrieve the current context
CONTEXT=$(kubectl config current-context)

# Retrieve the cluster name
CLUSTER_NAME=$(kubectl config get-contexts $CONTEXT --no-headers=true | awk '{print $3}')

# Retrieve the API endpoint
SERVER=$(kubectl config view -o jsonpath="{.clusters[?(@.name == \"${CLUSTER_NAME}\")].cluster.server}")

# Set up variables
KUBECONFIG_FILE=config USER=helm CA=ca.crt

# Set up config
kubectl config set-cluster $CLUSTER_NAME \
--kubeconfig=$KUBECONFIG_FILE \
--server=$SERVER \
--certificate-authority=$CA \
--embed-certs=true

# Set token credentials
kubectl config set-credentials \
$USER \
--kubeconfig=$KUBECONFIG_FILE \
--token=$TOKEN

# Set context entry
kubectl config set-context \
$USER \
--kubeconfig=$KUBECONFIG_FILE \
--cluster=$CLUSTER_NAME \
--user=$USER

# Set the current-context
kubectl config use-context $USER \
--kubeconfig=$KUBECONFIG_FILE
