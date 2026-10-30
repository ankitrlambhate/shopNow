#!/usr/bin/env bash
# Infrastructure integrity checks (Sprint 6). Run after the full pipeline, with AWS credentials.
# Usage: ./scripts/infra-tests.sh <cluster-name> [region]
# Optional env: NAMESPACE (shopnow-demo)  ECR_NAMESPACE (shopnow)  TF_STATE_BUCKET
set -uo pipefail

CLUSTER="${1:?cluster name required}"
REGION="${2:-ap-south-1}"
NS="${NAMESPACE:-shopnow-demo}"
ECR_NS="${ECR_NAMESPACE:-shopnow}"
FAILS=0

ok()  { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }
exists() { kubectl "$@" >/dev/null 2>&1; }

STATUS="$(aws eks describe-cluster --name "$CLUSTER" --region "$REGION" --query cluster.status --output text 2>/dev/null)"
[ "$STATUS" = "ACTIVE" ] && ok "EKS cluster is ACTIVE" || bad "EKS cluster status: ${STATUS:-unknown}"

aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1

READY_NODES="$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)"
[ "${READY_NODES:-0}" -ge 2 ] && ok "$READY_NODES nodes Ready" || bad "fewer than 2 Ready nodes"

for addon in vpc-cni kube-proxy coredns aws-ebs-csi-driver metrics-server; do
  S="$(aws eks describe-addon --cluster-name "$CLUSTER" --addon-name "$addon" --region "$REGION" --query addon.status --output text 2>/dev/null)"
  [ "$S" = "ACTIVE" ] && ok "add-on $addon ACTIVE" || bad "add-on $addon: ${S:-missing}"
done

exists top nodes && ok "metrics API works (kubectl top nodes)" || bad "kubectl top nodes failed (metrics-server)"

exists -n "$NS" get sts mongo         && ok "mongo StatefulSet exists"   || bad "mongo StatefulSet missing"
exists -n "$NS" get pvc mongo-data-mongo-0 && ok "mongo PVC exists"      || bad "mongo PVC missing"
for d in backend frontend admin; do
  exists -n "$NS" get deploy "$d" && ok "deployment $d exists" || bad "deployment $d missing"
  exists -n "$NS" get hpa "$d"    && ok "hpa $d exists"        || bad "hpa $d missing"
done
exists -n "$NS" get ingress shopnow-ingress && ok "ingress exists" || bad "ingress missing"
exists -n ingress-nginx get deploy ingress-nginx-controller && ok "ingress-nginx controller deployed" || bad "ingress-nginx missing"

exists -n monitoring get deploy kube-prometheus-stack-grafana && ok "Grafana deployed" || bad "Grafana missing"
exists -n monitoring get prometheusrule shopnow-alerts && ok "alert rules loaded" || bad "alert rules missing"
exists -n monitoring get servicemonitor shopnow-backend && ok "backend ServiceMonitor present" || bad "backend ServiceMonitor missing"

if [ -n "${TF_STATE_BUCKET:-}" ]; then
  V="$(aws s3api get-bucket-versioning --bucket "$TF_STATE_BUCKET" --query Status --output text 2>/dev/null)"
  [ "$V" = "Enabled" ] && ok "state bucket versioning enabled" || bad "state bucket versioning: ${V:-unknown}"
fi

for svc in frontend backend admin; do
  N="$(aws ecr describe-images --repository-name "$ECR_NS/$svc" --region "$REGION" --query 'length(imageDetails)' --output text 2>/dev/null)"
  [ "${N:-0}" -ge 1 ] && ok "ECR $ECR_NS/$svc has $N image(s)" || bad "no images in ECR $ECR_NS/$svc"
done

echo
if [ "$FAILS" -eq 0 ]; then echo "All infrastructure checks passed."; else echo "$FAILS check(s) failed."; exit 1; fi
