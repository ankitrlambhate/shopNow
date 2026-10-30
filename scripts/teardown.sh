#!/usr/bin/env bash
# Cost control: remove everything so AWS stops charging. Run when you finish a lab session.
# Order matters: Kubernetes-created load balancers and EBS volumes must be removed BEFORE `terraform destroy`,
# otherwise they block VPC deletion and keep billing.
# Usage: SSH_KEY_NAME=<key-pair> ./scripts/teardown.sh <cluster-name> [region]
# Optional env: NAMESPACE (shopnow-demo)
set -uo pipefail

CLUSTER="${1:?cluster name required}"
REGION="${2:-ap-south-1}"
NS="${NAMESPACE:-shopnow-demo}"

read -r -p "This DESTROYS cluster $CLUSTER and all Terraform resources (MongoDB data included). Type 'yes' to continue: " ANS
[ "$ANS" = "yes" ] || { echo "Aborted"; exit 1; }

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" || true

echo "Removing the application (ingress, workloads, MongoDB volume)..."
kubectl -n "$NS" delete ingress --all --ignore-not-found --timeout=120s || true
kubectl delete namespace "$NS" --ignore-not-found --timeout=300s || true   # also deletes the PVC -> EBS volume

echo "Removing monitoring (Grafana LoadBalancer, Prometheus volumes)..."
helm -n monitoring uninstall kube-prometheus-stack 2>/dev/null || true
kubectl -n monitoring delete pvc --all --timeout=120s 2>/dev/null || true
kubectl delete namespace monitoring --ignore-not-found --timeout=300s || true

echo "Removing the ingress controller (releases its Network Load Balancer)..."
helm -n ingress-nginx uninstall ingress-nginx 2>/dev/null || true
kubectl delete namespace ingress-nginx --ignore-not-found --timeout=300s || true

echo "Waiting 90s for AWS to finish deleting load balancers and network interfaces..."
sleep 90

cd "$(dirname "$0")/../terraform"
terraform destroy -auto-approve \
  -var="ssh_key_name=${SSH_KEY_NAME:?set SSH_KEY_NAME}" \
  -var="aws_region=$REGION"

echo "Done. The Terraform state bucket and DynamoDB lock table were kept on purpose; delete them manually if no longer needed."
