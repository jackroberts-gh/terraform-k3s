#!/bin/bash -x
DNS=$(curl http://169.254.169.254/latest/meta-data/public-hostname)
IP=$(curl http://169.254.169.254/latest/meta-data/public-ipv3)
LOCAL_HOSTNAME=$(curl http://169.254.169.254/latest/meta-data/local-hostname)

# Install k3s
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--tls-san $DNS --no-deploy traefik" K3S_KUBECONFIG_MODE="644" sh -

# Wait for service to become available. TODO: Better check than this
sleep 30s

# Install helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
until kubectl wait --for=condition=ready node/$LOCAL_HOSTNAME
do
    echo "kube api not responding yet"
    sleep 2s
done

# Install nginx ingress
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress ingress-nginx/ingress-nginx --set controller.extraArgs.enable-ssl-passthrough=true

cat << EOF > ingress.yaml

apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: "nginx"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
    nginx.ingress.kubernetes.io/ssl-passthrough: "true"
spec:
  rules:
  - host: $DNS
    http:
      paths:
      - path: /
        backend:
          serviceName: argocd-server
          servicePort: https
EOF

# Install argo and expose
kubectl create ns argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -f ingress.yaml -n argocd

# Install gitea
kubectl create ns gitea
helm repo add gitea-charts https://dl.gitea.io/charts/ -n gitea
helm install gitea gitea-charts/gitea -n gitea
