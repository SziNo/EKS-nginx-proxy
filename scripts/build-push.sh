#!/usr/bin/env bash
# Mindkét image buildelése linux/amd64-re és feltöltése az ECR-be.
# Használat: ./scripts/build-push.sh 1.0.0
set -euo pipefail

TAG="${1:-1.0.0}"
REGION="$(terraform -chdir=terraform output -raw region)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in service-a service-b; do
  # --platform: ha ARM (pl. Apple Silicon) gépen buildelsz, a node-ok viszont x86-osak
  docker buildx build --platform linux/amd64 -t "${REGISTRY}/${svc}:${TAG}" --push "apps/${svc}"
done

echo "Kész: ${REGISTRY}/service-a:${TAG} és ${REGISTRY}/service-b:${TAG}"
