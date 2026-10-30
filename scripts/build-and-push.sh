#!/usr/bin/env bash
# Manual build + push of the three images (the README refers to this script; it was removed from the repo).
# Jenkins does the same thing in jenkins/Jenkinsfile.app-cicd.
#
# Usage: scripts/build-and-push.sh <registry>/<namespace> <tag> <path-prefix>
# Example:
#   scripts/build-and-push.sh 123456789012.dkr.ecr.ap-south-1.amazonaws.com/shopnow v1 shopnow
# The registry/namespace must match the ECR repositories created by Terraform (<namespace>/frontend|backend|admin).
set -euo pipefail

REGISTRY="${1:?usage: $0 <registry>/<namespace> <tag> <path-prefix>}"
TAG="${2:?tag required}"
PREFIX="${3:?path prefix required (the value baked into the React apps as /<prefix>)}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Logging in to ECR..."
REGION="$(echo "$REGISTRY" | sed -E 's/^[0-9]+\.dkr\.ecr\.([a-z0-9-]+)\.amazonaws\.com.*/\1/')"
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "${REGISTRY%%/*}"

docker build -t "$REGISTRY/backend:$TAG" "$ROOT/backend"
docker build --build-arg USER_NAME="$PREFIX" -t "$REGISTRY/frontend:$TAG" "$ROOT/frontend"
docker build --build-arg USER_NAME="$PREFIX" -t "$REGISTRY/admin:$TAG" "$ROOT/admin"

for svc in backend frontend admin; do
  docker push "$REGISTRY/$svc:$TAG"
done

echo "Pushed $REGISTRY/{backend,frontend,admin}:$TAG"
