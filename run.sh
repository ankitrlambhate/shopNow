#!/usr/bin/env bash
# run.sh - runs the whole shopNow assignment flow from your own machine (or from the Jenkins agent):
#   Terraform (VPC, EKS, ECR, EC2)  ->  Ansible (EC2 configuration)  ->  Docker build/push + Kubernetes deploy on EKS
#   ->  Prometheus + Grafana monitoring  ->  tests.
# The Jenkinsfiles in jenkins/ run the same steps inside Jenkins (see README.md).
#
# Usage:  ./run.sh <command>
#   check        verify tools, AWS credentials, key pair and config (changes nothing)
#   backend      create the S3 bucket + DynamoDB table for Terraform state (once)
#   infra        Terraform: VPC, EKS, ECR, EC2 tools host                       (~15-20 min)
#   configure    Ansible: configure the EC2 tools host
#   app          test, build and push 3 images, deploy to EKS, smoke test        (~10 min)
#   monitoring   install Prometheus + Grafana, alert rules, dashboard            (~5 min)
#   test         run the smoke tests and the infrastructure checks
#   status       print URLs and what is running
#   all          check, backend, infra, configure, app, monitoring, test, status
#   destroy      delete EVERYTHING that costs money (run this when you finish)
#
# Configuration: cp config.env.example config.env, then edit config.env. Values in that file take precedence over
# exported variables. Use CONFIG_FILE=/path/to/other.env ./run.sh <command> to point at a different file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="${CONFIG_FILE:-$ROOT/config.env}"
if [ -f "$CONFIG" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$CONFIG"
  set +a
fi

AWS_REGION="${AWS_REGION:-ap-south-1}"
ENVIRONMENT="${ENVIRONMENT:-dev}"
APP_PATH_PREFIX="${APP_PATH_PREFIX:-shopnow}"
NAMESPACE="${NAMESPACE:-shopnow-demo}"
ECR_NAMESPACE="${ECR_NAMESPACE:-shopnow}"
GRAFANA_SERVICE_TYPE="${GRAFANA_SERVICE_TYPE:-ClusterIP}"
CLUSTER_NAME="shopnow-${ENVIRONMENT}-eks"      # Terraform names the cluster <project>-<environment>-eks
export AWS_REGION AWS_DEFAULT_REGION="$AWS_REGION" ENVIRONMENT APP_PATH_PREFIX NAMESPACE ECR_NAMESPACE

mkdir -p "$ROOT/.run"
START_TS=$(date +%s)

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  ok\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m  warn\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ERROR\033[0m %s\n' "$*" >&2; exit 1; }

need_cmd()  { command -v "$1" >/dev/null 2>&1 || die "'$1' is not installed or not on PATH ($2)"; }
need_vars() { local v; for v in "$@"; do [ -n "${!v:-}" ] || die "$v is not set. Edit config.env (see config.env.example)."; done; }

alnum_check() {
  [[ "${!1}" =~ ^[A-Za-z0-9]+$ ]] || die "$1 must be alphanumeric only (A-Z a-z 0-9): it is placed in a connection string."
}

resolve_account() {
  ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
    || die "AWS credentials not working. Run 'aws configure' or export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY."
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  TF_STATE_BUCKET="shopnow-tfstate-${ACCOUNT_ID}"   # same names as scripts/bootstrap-tf-backend.sh
  TF_LOCK_TABLE="shopnow-tf-lock"
  export ACCOUNT_ID ECR_REGISTRY TF_STATE_BUCKET TF_LOCK_TABLE
}

resolve_admin_cidr() {
  if [ -z "${ADMIN_CIDR:-}" ]; then
    local ip
    ip="$(curl -fsS --max-time 8 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
    [ -n "$ip" ] || die "Could not detect your public IP. Set ADMIN_CIDR=<your-ip>/32 in config.env."
    ADMIN_CIDR="$ip/32"
    warn "ADMIN_CIDR not set: using your current public IP $ADMIN_CIDR for SSH and the EKS API"
  fi
  export ADMIN_CIDR
}

kubeconfig() {
  aws eks update-kubeconfig --region "$AWS_REGION" --name "$CLUSTER_NAME" >/dev/null
}

tf() { terraform -chdir="$ROOT/terraform" "$@"; }

tf_init() {
  resolve_account
  tf init -input=false -reconfigure \
    -backend-config="bucket=$TF_STATE_BUCKET" \
    -backend-config="dynamodb_table=$TF_LOCK_TABLE" \
    -backend-config="region=$AWS_REGION" \
    -backend-config="key=shopnow/${ENVIRONMENT}/terraform.tfstate" >/dev/null
}

# ------------------------------------------------------------------------------------------------ commands

cmd_check() {
  log "Checking tools"
  need_cmd aws "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  need_cmd terraform "https://developer.hashicorp.com/terraform/install"
  need_cmd kubectl "https://kubernetes.io/docs/tasks/tools/"
  need_cmd helm "https://helm.sh/docs/intro/install/"
  need_cmd docker "https://docs.docker.com/engine/install/"
  need_cmd ansible-playbook "pip install ansible"
  need_cmd python3 "install Python 3"
  need_cmd ssh "install an OpenSSH client"
  need_cmd curl "install curl"
  python3 -c "import yaml" 2>/dev/null || die "Python module 'yaml' missing: pip install pyyaml"
  docker info >/dev/null 2>&1 || die "Docker is installed but the daemon is not reachable (is Docker running? is your user in the docker group?)"
  ok "aws, terraform, kubectl, helm, docker, ansible-playbook, python3 (+pyyaml), ssh, curl"

  log "Checking configuration"
  need_vars SSH_KEY_NAME SSH_KEY_FILE MONGO_APP_PASSWORD MONGO_ROOT_PASSWORD GRAFANA_ADMIN_PASSWORD
  alnum_check MONGO_APP_PASSWORD
  alnum_check MONGO_ROOT_PASSWORD
  [ -f "$SSH_KEY_FILE" ] || die "SSH_KEY_FILE '$SSH_KEY_FILE' not found"
  chmod 400 "$SSH_KEY_FILE" 2>/dev/null || true
  ok "required variables set; SSH key file found"

  log "Checking AWS"
  resolve_account
  ok "AWS account $ACCOUNT_ID, region $AWS_REGION"
  aws ec2 describe-key-pairs --key-names "$SSH_KEY_NAME" --region "$AWS_REGION" >/dev/null 2>&1 \
    || die "EC2 key pair '$SSH_KEY_NAME' does not exist in $AWS_REGION. Create it in the EC2 console (Key Pairs) and download the .pem file."
  ok "key pair $SSH_KEY_NAME exists in $AWS_REGION"
  resolve_admin_cidr
  ok "admin CIDR $ADMIN_CIDR"

  echo
  echo "Cluster name will be: $CLUSTER_NAME | ECR: $ECR_REGISTRY/$ECR_NAMESPACE/{frontend,backend,admin} | namespace: $NAMESPACE"
  echo "App URLs will be:     http://<load-balancer>/$APP_PATH_PREFIX  and  http://<load-balancer>/$APP_PATH_PREFIX-admin"
  echo "All checks passed."
}

cmd_backend() {
  log "Terraform remote state (S3 + DynamoDB)"
  resolve_account
  "$ROOT/scripts/bootstrap-tf-backend.sh" "$AWS_REGION" "$TF_STATE_BUCKET"
}

cmd_infra() {
  need_vars SSH_KEY_NAME
  resolve_admin_cidr
  log "Terraform init (state bucket s3://shopnow-tfstate-<account>)"
  tf_init
  log "Terraform validate"
  tf validate
  log "Terraform apply: VPC, subnets, EKS, ECR, EC2 (EKS takes about 15 minutes)"
  tf apply -input=false -auto-approve \
    -var="aws_region=$AWS_REGION" \
    -var="environment=$ENVIRONMENT" \
    -var="ssh_key_name=$SSH_KEY_NAME" \
    -var="admin_cidr=$ADMIN_CIDR" \
    -var="ecr_namespace=$ECR_NAMESPACE"
  tf output -json > "$ROOT/.run/tf-outputs.json"
  kubeconfig
  ok "infrastructure ready. Cluster: $CLUSTER_NAME | tools host: $(tf output -raw bastion_public_ip)"
  kubectl get nodes || true
}

cmd_configure() {
  need_vars SSH_KEY_FILE
  tf_init
  local ip
  ip="$(tf output -raw bastion_public_ip 2>/dev/null)" || die "No tools host found in Terraform state. Run './run.sh infra' first."

  log "Waiting for SSH on $ip"
  local i
  for i in $(seq 1 40); do
    if timeout 4 bash -c "exec 3<>/dev/tcp/$ip/22" 2>/dev/null; then break; fi
    [ "$i" = 40 ] && die "SSH on $ip:22 not reachable after ~5 minutes. Check ADMIN_CIDR includes your current IP."
    sleep 8
  done
  ok "SSH is reachable"

  cat > "$ROOT/.run/inventory.ini" <<EOF
[role_tools]
tools-host ansible_host=$ip ansible_user=ubuntu ansible_ssh_private_key_file=$SSH_KEY_FILE
EOF

  log "Ansible: configure the tools host (Docker, kubectl, AWS CLI, helm, node_exporter, SSH hardening)"
  export ANSIBLE_INVENTORY_ENABLED=ini ANSIBLE_HOST_KEY_CHECKING=False EKS_CLUSTER_NAME="$CLUSTER_NAME"
  export ANSIBLE_ROLES_PATH="$ROOT/ansible/roles${ANSIBLE_ROLES_PATH:+:$ANSIBLE_ROLES_PATH}"
  ( cd "$ROOT/ansible"
    ansible-playbook playbooks/site.yml   -i "$ROOT/.run/inventory.ini"
    log "Ansible: verify the configuration"
    ansible-playbook playbooks/verify.yml -i "$ROOT/.run/inventory.ini" )
  ok "tools host configured and verified"
}

cmd_app() {
  need_vars MONGO_APP_PASSWORD MONGO_ROOT_PASSWORD
  alnum_check MONGO_APP_PASSWORD
  alnum_check MONGO_ROOT_PASSWORD
  resolve_account
  kubeconfig
  kubectl get nodes >/dev/null 2>&1 || die "Cannot reach the cluster $CLUSTER_NAME. Run './run.sh infra' first, and check ADMIN_CIDR includes your current IP."

  IMAGE_TAG="$(date +%Y%m%d%H%M%S)-$(git rev-parse --short HEAD 2>/dev/null || echo local)"
  export IMAGE_TAG
  log "Image tag: $IMAGE_TAG"

  log "Backend unit tests"
  docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e npm_config_cache=/tmp/.npm \
    -v "$ROOT/backend":/app -w /app node:20-alpine sh -c "npm ci --no-audit --no-fund && npm test"

  log "Build images"
  docker build -t "$ECR_REGISTRY/$ECR_NAMESPACE/backend:$IMAGE_TAG" backend
  docker build --build-arg USER_NAME="$APP_PATH_PREFIX" -t "$ECR_REGISTRY/$ECR_NAMESPACE/frontend:$IMAGE_TAG" frontend
  docker build --build-arg USER_NAME="$APP_PATH_PREFIX" -t "$ECR_REGISTRY/$ECR_NAMESPACE/admin:$IMAGE_TAG" admin

  log "Push images to ECR"
  aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null
  local svc
  for svc in backend frontend admin; do docker push "$ECR_REGISTRY/$ECR_NAMESPACE/$svc:$IMAGE_TAG" >/dev/null && ok "pushed $svc"; done

  log "Cluster add-ons (gp3 storage class, ingress-nginx load balancer)"
  "$ROOT/scripts/install-cluster-addons.sh"

  log "Deploy to EKS"
  "$ROOT/scripts/render-manifests.sh" "$ROOT/rendered"
  kubectl apply -f rendered/namespace/
  "$ROOT/scripts/create-secrets.sh"
  kubectl apply -f rendered/database/
  kubectl -n "$NAMESPACE" rollout status statefulset/mongo --timeout=420s
  kubectl apply -f rendered/backend/
  kubectl -n "$NAMESPACE" rollout status deployment/backend --timeout=300s
  kubectl apply -f rendered/frontend/ -f rendered/admin/
  kubectl -n "$NAMESPACE" rollout status deployment/frontend --timeout=300s
  kubectl -n "$NAMESPACE" rollout status deployment/admin --timeout=300s
  kubectl apply -f rendered/ingress/
  kubectl -n "$NAMESPACE" get deploy,sts,svc,hpa,ing

  log "Smoke test"
  "$ROOT/scripts/smoke-test.sh"
}

cmd_monitoring() {
  need_vars GRAFANA_ADMIN_PASSWORD
  tf_init
  kubeconfig
  kubectl get nodes >/dev/null 2>&1 || die "Cannot reach the cluster $CLUSTER_NAME. Run './run.sh infra' first."
  export BASTION_PRIVATE_IP="${BASTION_PRIVATE_IP:-$(tf output -raw bastion_private_ip 2>/dev/null || true)}"
  export JENKINS_HOST="${JENKINS_HOST:-}"

  log "Prepare monitoring configuration"
  "$ROOT/scripts/prepare-monitoring.sh"

  log "Install Prometheus + Grafana + Alertmanager (kube-prometheus-stack)"
  kubectl apply -f kubernetes/pre-req/storageclass-gp3.yaml
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
    -n monitoring --create-namespace \
    -f monitoring/values.rendered.yaml \
    --set grafana.adminPassword="$GRAFANA_ADMIN_PASSWORD" \
    --set grafana.service.type="$GRAFANA_SERVICE_TYPE" \
    --wait --timeout 15m

  log "Alert rules, ServiceMonitors, Grafana dashboard"
  kubectl apply -f monitoring/alert-rules.rendered.yaml
  kubectl apply -f monitoring/servicemonitors.rendered.yaml
  kubectl apply -f monitoring/grafana-dashboard-shopnow.yaml
  kubectl -n monitoring rollout status deployment/kube-prometheus-stack-grafana --timeout=300s
  ok "monitoring installed"
  print_grafana
}

cmd_test() {
  tf_init
  kubeconfig
  log "Smoke test (frontend, admin, API, order flow, replicas)"
  "$ROOT/scripts/smoke-test.sh"
  log "Infrastructure checks (cluster, add-ons, workloads, monitoring, ECR)"
  TF_STATE_BUCKET="$TF_STATE_BUCKET" "$ROOT/scripts/infra-tests.sh" "$CLUSTER_NAME" "$AWS_REGION"
}

print_grafana() {
  echo "Grafana login: admin / <GRAFANA_ADMIN_PASSWORD>"
  if [ "$GRAFANA_SERVICE_TYPE" = "LoadBalancer" ]; then
    echo "Grafana URL:   http://$(kubectl -n monitoring get svc kube-prometheus-stack-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)"
  else
    echo "Grafana:       kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80   then open http://localhost:3000"
  fi
  echo "Prometheus:    kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090   then open http://localhost:9090"
}

cmd_status() {
  kubeconfig
  local host
  host="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  log "shopNow status"
  echo "Cluster:        $CLUSTER_NAME ($AWS_REGION)"
  echo "Customer app:   http://${host:-<pending>}/$APP_PATH_PREFIX"
  echo "Admin app:      http://${host:-<pending>}/$APP_PATH_PREFIX-admin"
  kubectl -n "$NAMESPACE" get pods,hpa 2>/dev/null || true
  print_grafana
}

cmd_destroy() {
  need_vars SSH_KEY_NAME
  tf_init
  kubeconfig || true
  export SSH_KEY_NAME ENVIRONMENT NAMESPACE
  "$ROOT/scripts/teardown.sh" "$CLUSTER_NAME" "$AWS_REGION"
  log "Now verify in the AWS console (region $AWS_REGION) that no EKS cluster, NAT gateway, load balancer or EC2 instance remains."
}

cmd_all() {
  cmd_check
  cmd_backend
  cmd_infra
  cmd_configure
  cmd_app
  cmd_monitoring
  cmd_test
  cmd_status
  local mins=$(( ($(date +%s) - START_TS) / 60 ))
  log "Everything is up (took ${mins} minutes). Running cost is about \$0.31/hour: run './run.sh destroy' when you finish."
}

usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "$0"; }

case "${1:-help}" in
  check)      cmd_check ;;
  backend)    cmd_backend ;;
  infra)      cmd_infra ;;
  configure)  cmd_configure ;;
  app)        cmd_app ;;
  monitoring) cmd_monitoring ;;
  test)       cmd_test ;;
  status)     cmd_status ;;
  all)        cmd_all ;;
  destroy)    cmd_destroy ;;
  help|-h|--help) usage ;;
  *) echo "Unknown command: $1" >&2; usage; exit 1 ;;
esac
