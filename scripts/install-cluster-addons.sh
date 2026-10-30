#!/usr/bin/env bash
# Installs cluster-level prerequisites the application needs. Idempotent (safe on every pipeline run).
#   - gp3 StorageClass (for MongoDB / monitoring volumes; needs the EBS CSI add-on from Terraform)
#   - ingress-nginx controller (AWS Network Load Balancer) with Prometheus metrics enabled
# metrics-server (needed by the HPAs) is installed by Terraform as an EKS managed add-on.
# Expects kubeconfig to point at the cluster.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

kubectl apply -f "$ROOT/kubernetes/pre-req/storageclass-gp3.yaml"

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
helm repo update ingress-nginx >/dev/null

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set-string controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"=nlb \
  --set controller.metrics.enabled=true \
  --set controller.replicaCount=2 \
  --wait --timeout 10m

echo "Waiting for the load balancer hostname..."
for i in $(seq 1 40); do
  HOST="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$HOST" ] && break
  sleep 10
done
echo "Ingress endpoint: ${HOST:-<pending>}"

echo "metrics-server status:"
kubectl -n kube-system get deploy metrics-server 2>/dev/null || echo "  metrics-server not found (check the Terraform add-on)"
