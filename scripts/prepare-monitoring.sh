#!/usr/bin/env bash
# Renders the monitoring files (used by run.sh and by jenkins/Jenkinsfile.monitoring).
#   monitoring/values.rendered.yaml         <- Helm values, with optional scrape targets filled in or removed
#   monitoring/alert-rules.rendered.yaml    <- ${NAMESPACE} replaced
#   monitoring/servicemonitors.rendered.yaml
# Env: NAMESPACE (default shopnow-demo)
#      JENKINS_HOST         hostname only (no https://). Empty = no Jenkins scrape job / alert webhook
#      BASTION_PRIVATE_IP   private IP of the tools host. Empty = no node_exporter scrape job
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export NAMESPACE="${NAMESPACE:-shopnow-demo}"
export JENKINS_HOST="${JENKINS_HOST:-}"
export BASTION_PRIVATE_IP="${BASTION_PRIVATE_IP:-}"

python3 - <<'PY'
import os
try:
    import yaml
except ImportError:
    raise SystemExit("pyyaml is required: pip install pyyaml")

src = "monitoring/kube-prometheus-stack-values.yaml"
out = "monitoring/values.rendered.yaml"
d = yaml.safe_load(open(src))
spec = d["prometheus"]["prometheusSpec"]
am = d["alertmanager"]["config"]
jenkins = os.environ["JENKINS_HOST"].strip()
bastion = os.environ["BASTION_PRIVATE_IP"].strip()

def keep(cfg):
    name = cfg["job_name"]
    if name == "jenkins":
        if not jenkins:
            return False
        cfg["static_configs"][0]["targets"] = [jenkins]
    if name == "bastion-node":
        if not bastion:
            return False
        cfg["static_configs"][0]["targets"] = [bastion + ":9100"]
    return True

spec["additionalScrapeConfigs"] = [c for c in spec["additionalScrapeConfigs"] if keep(c)]
if jenkins:
    for r in am["receivers"]:
        for w in r.get("webhook_configs", []):
            w["url"] = w["url"].replace("JENKINS_HOST", jenkins)
else:
    am["route"]["routes"] = []
    am["receivers"] = [r for r in am["receivers"] if r["name"] == "default"]

yaml.safe_dump(d, open(out, "w"), sort_keys=False)
print("Rendered %s (jenkins=%s, bastion=%s)" % (out, bool(jenkins), bool(bastion)))
PY

for f in alert-rules servicemonitors; do
  sed "s/\${NAMESPACE}/$NAMESPACE/g" "monitoring/$f.yaml" > "monitoring/$f.rendered.yaml"
done
echo "Rendered alert-rules and servicemonitors for namespace $NAMESPACE"
