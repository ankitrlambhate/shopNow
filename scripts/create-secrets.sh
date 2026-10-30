#!/usr/bin/env bash
# Creates/updates the Kubernetes Secrets used by MongoDB and the backend. Idempotent.
# Passwords come from environment variables (Jenkins injects them from the credential store),
# so nothing sensitive is committed to Git.
#
# Required env: NAMESPACE MONGO_APP_PASSWORD MONGO_ROOT_PASSWORD
# Optional env: MONGO_APP_USER (default shopuser) MONGO_ROOT_USER (default root)
#
# Use alphanumeric passwords: they are embedded in a connection string and a shell script.
set -euo pipefail

: "${NAMESPACE:?}" "${MONGO_APP_PASSWORD:?}" "${MONGO_ROOT_PASSWORD:?}"
APP_USER="${MONGO_APP_USER:-shopuser}"
ROOT_USER="${MONGO_ROOT_USER:-root}"

if ! [[ "$MONGO_APP_PASSWORD" =~ ^[A-Za-z0-9]+$ && "$MONGO_ROOT_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
  echo "ERROR: MongoDB passwords must be alphanumeric (A-Z a-z 0-9)." >&2
  exit 1
fi

URI="mongodb://${APP_USER}:${MONGO_APP_PASSWORD}@mongo-0.mongo:27017/shopnow?authSource=admin"

kubectl -n "$NAMESPACE" create secret generic mongo-secret \
  --from-literal=root-username="$ROOT_USER" \
  --from-literal=root-password="$MONGO_ROOT_PASSWORD" \
  --from-literal=app-user="$APP_USER" \
  --from-literal=app-password="$MONGO_APP_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl -n "$NAMESPACE" create secret generic backend-secret \
  --from-literal=mongodb-uri="$URI" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secrets mongo-secret and backend-secret applied in namespace $NAMESPACE"
