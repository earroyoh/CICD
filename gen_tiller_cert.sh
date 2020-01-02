#!/bin/bash
# Usage: gen_tiller_cert.sh NAMESPACE IP
#
cat <<EOF > tiller_csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = ES
ST = Madrid
L = Madrid
O = Self-O
OU = Self-OU
CN = tiller-deploy.svc.cluster.local

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = tiller-deploy
DNS.2 = tiller-deploy.$1
DNS.3 = tiller-deploy.$1.svc
DNS.4 = tiller-deploy.$1.svc.cluster
DNS.5 = tiller-deploy.$1.svc.cluster.local
IP.1 = $2

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl genrsa -out tiller.key 2048
openssl req -new -key tiller.key -out tiller.csr -config tiller_csr.conf
openssl x509 -req -in tiller.csr \
-CA /etc/kubernetes/pki/ca.crt \
-CAkey /etc/kubernetes/pki/ca.key \
-CAcreateserial -out tiller.crt -days 100 \
-extensions v3_ext -extfile tiller_csr.conf

cat <<EOF > helm_csr.conf
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = ES
ST = Madrid
L = Madrid
O = Self-O
OU = Self-OU
CN = helm.svc.cluster.local

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = helm
DNS.2 = helm.$1
DNS.3 = helm.$1.svc
DNS.4 = helm.$1.svc.cluster
DNS.5 = helm.$1.svc.cluster.local
IP.1 = $2

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl genrsa -out helm.key 2048
openssl req -new -key helm.key -out helm.csr -config helm_csr.conf
openssl x509 -req -in helm.csr \
-CA /etc/kubernetes/pki/ca.crt \
-CAkey /etc/kubernetes/pki/ca.key \
-CAcreateserial -out helm.crt -days 100 \
-extensions v3_ext -extfile helm_csr.conf

export HELM_TLS_CA_CERT=/etc/kubernetes/pki/ca.crt
export HELM_TLS_CERT=helm.crt
export HELM_TLS_KEY=helm.key
export HELM_TLS_ENABLE="true"
export HELM_TLS_VERIFY="true"
