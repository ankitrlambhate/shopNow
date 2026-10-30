#!/usr/bin/env bash
# Renders the templated manifests in kubernetes/k8s-manifests into ./rendered
# Required env: NAMESPACE ECR_REGISTRY ECR_NAMESPACE IMAGE_TAG APP_PATH_PREFIX
# Only these variables are substituted, so other "$" characters (nginx rewrites, shell scripts) stay intact.
set -euo pipefail

: "${NAMESPACE:?}" "${ECR_REGISTRY:?}" "${ECR_NAMESPACE:?}" "${IMAGE_TAG:?}" "${APP_PATH_PREFIX:?}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/rendered}"
VARS='${NAMESPACE} ${ECR_REGISTRY} ${ECR_NAMESPACE} ${IMAGE_TAG} ${APP_PATH_PREFIX}'

render() {
  if command -v envsubst >/dev/null 2>&1; then
    envsubst "$VARS" < "$1"
  else
    # portable fallback when gettext-base is not installed
    python3 - "$1" <<'PY'
import os, sys
text = open(sys.argv[1]).read()
for k in ("NAMESPACE", "ECR_REGISTRY", "ECR_NAMESPACE", "IMAGE_TAG", "APP_PATH_PREFIX"):
    text = text.replace("${%s}" % k, os.environ[k])
sys.stdout.write(text)
PY
  fi
}

rm -rf "$OUT"
while IFS= read -r f; do
  rel="${f#"$ROOT"/kubernetes/k8s-manifests/}"
  mkdir -p "$OUT/$(dirname "$rel")"
  render "$f" > "$OUT/$rel"
done < <(find "$ROOT/kubernetes/k8s-manifests" -name '*.yaml' | sort)

echo "Rendered manifests into $OUT"
