#!/usr/bin/env bash
# Post-deployment smoke / functional test for shopNow, run through the public ingress endpoint.
# Expects kubeconfig to point at the cluster.
#
# Env: NAMESPACE (default shopnow-demo)  APP_PATH_PREFIX (default shopnow)
#      RETRIES (default 30, 10s apart)   WRITE_TESTS=true|false (default true)
set -euo pipefail

NAMESPACE="${NAMESPACE:-shopnow-demo}"
PREFIX="${APP_PATH_PREFIX:-shopnow}"
RETRIES="${RETRIES:-30}"
WRITE_TESTS="${WRITE_TESTS:-true}"
FAILS=0

pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILS=$((FAILS+1)); }

echo "== Waiting for the ingress load balancer =="
HOST=""
for _ in $(seq 1 "$RETRIES"); do
  HOST="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)"
  [ -n "$HOST" ] && break
  sleep 10
done
[ -z "$HOST" ] && { echo "FAIL: ingress has no load balancer hostname"; exit 1; }
BASE="http://$HOST"
echo "Endpoint: $BASE/$PREFIX"

echo "== Waiting for the app to answer through the ingress =="
for i in $(seq 1 "$RETRIES"); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$BASE/$PREFIX/" || true)"
  [ "$code" = "200" ] && break
  [ "$i" = "$RETRIES" ] && { echo "FAIL: $BASE/$PREFIX/ never returned 200 (last code: $code)"; exit 1; }
  sleep 10
done

# json_field <url> <python-expression-on-d>  -> prints the value
json_eval() {
  curl -fsS --max-time 10 "$1" | python3 -c "import sys, json; d = json.load(sys.stdin); print($2)"
}

echo "== Customer app (frontend) =="
curl -fsS --max-time 10 "$BASE/$PREFIX/" | grep -q 'id="root"' && pass "frontend serves the React page" || fail "frontend page missing root element"
[ "$(json_eval "$BASE/$PREFIX/api/health" "d['status']")" = "OK" ] && pass "frontend -> backend proxy (/api/health)" || fail "frontend -> backend proxy"
COUNT="$(json_eval "$BASE/$PREFIX/api/products" "len(d['products'])" 2>/dev/null || echo 0)"
[ "${COUNT:-0}" -ge 1 ] && pass "products API returns $COUNT products (MongoDB connected, seed ran)" || fail "products API returned no products"
CATS="$(json_eval "$BASE/$PREFIX/api/categories" "len(d)" 2>/dev/null || echo 0)"
[ "${CATS:-0}" -ge 1 ] && pass "categories API returns $CATS categories" || fail "categories API empty"

echo "== Admin app =="
curl -fsS --max-time 10 "$BASE/$PREFIX-admin/" | grep -q 'id="root"' && pass "admin serves the React page" || fail "admin page missing root element"
json_eval "$BASE/$PREFIX-admin/api/analytics/dashboard" "'totalOrders' in d" 2>/dev/null | grep -q True \
  && pass "admin -> backend proxy (/api/analytics/dashboard)" || fail "admin API proxy (check admin/nginx/default.conf /api/ block)"

if [ "$WRITE_TESTS" = "true" ]; then
  echo "== Order flow (create -> fetch by token -> cancel) =="
  PRODUCT="$(curl -fsS --max-time 10 "$BASE/$PREFIX/api/products?limit=1")"
  PAYLOAD="$(echo "$PRODUCT" | python3 -c "
import sys, json
p = json.load(sys.stdin)['products'][0]
print(json.dumps({
  'customerDetails': {'name': 'Pipeline Smoke Test', 'phone': '0000000000', 'email': 'smoke-test@example.com'},
  'items': [{'_id': p['_id'], 'name': p['name'], 'price': p['price'], 'quantity': 1, 'image': p['image']}],
  'total': p['price']}))")"
  CREATED="$(curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$BASE/$PREFIX/api/invoices" || true)"
  INV_ID="$(echo "$CREATED" | python3 -c "import sys, json; print(json.load(sys.stdin)['invoice']['_id'])" 2>/dev/null || true)"
  TOKEN="$(echo "$CREATED" | python3 -c "import sys, json; print(json.load(sys.stdin)['invoice']['token'])" 2>/dev/null || true)"
  if [ -n "$INV_ID" ] && [ -n "$TOKEN" ]; then
    pass "order created (token $TOKEN)"
    [ "$(json_eval "$BASE/$PREFIX/api/invoices/token/$TOKEN" "d['status']")" = "pending" ] && pass "order fetched by token (pending)" || fail "order lookup by token"
    UPD="$(curl -fsS --max-time 10 -X PUT -H 'Content-Type: application/json' -d '{"status":"cancelled"}' "$BASE/$PREFIX-admin/api/invoices/$INV_ID/status" || true)"
    echo "$UPD" | grep -q '"cancelled"' && pass "order cancelled via the admin path" || fail "admin status update"
  else
    fail "order creation failed: $CREATED"
  fi
else
  echo "(write tests skipped)"
fi

echo "== Kubernetes state =="
ready() { kubectl -n "$NAMESPACE" get "$1" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0; }
[ "$(ready sts/mongo)" -ge 1 ]       && pass "mongo ready"           || fail "mongo not ready"
[ "$(ready deploy/backend)" -ge 2 ]  && pass "backend >= 2 replicas" || fail "backend has fewer than 2 ready replicas"
[ "$(ready deploy/frontend)" -ge 2 ] && pass "frontend >= 2 replicas" || fail "frontend has fewer than 2 ready replicas"
[ "$(ready deploy/admin)" -ge 1 ]    && pass "admin >= 1 replica"    || fail "admin not ready"
kubectl -n "$NAMESPACE" get hpa

echo
if [ "$FAILS" -eq 0 ]; then
  echo "All smoke tests passed."
else
  echo "$FAILS smoke test(s) failed."
  exit 1
fi
