#!/usr/bin/env bash
# Mindkét image buildelése linux/amd64-re és feltöltése az ECR-be.
# A repók neve <cluster_name>/<szolgáltatás>, pl. szino-nginx-proxy-demo/service-a.
# Használat: ./scripts/build-push.sh 1.0.0
set -euo pipefail

TAG="${1:-1.0.0}"
REGION="$(terraform -chdir=terraform output -raw region)"
CLUSTER="$(terraform -chdir=terraform output -raw cluster_name)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"

# A login a regiszterre szól (fiókonként és régiónként egy), nem az egyes repókra
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in service-a service-b; do
  # --platform: ha ARM (pl. Apple Silicon) gépen buildelsz, a node-ok viszont x86-osak
  docker buildx build --platform linux/amd64 -t "${REGISTRY}/${CLUSTER}/${svc}:${TAG}" --push "apps/${svc}"
done

echo "Kész: ${REGISTRY}/${CLUSTER}/service-a:${TAG} és ${REGISTRY}/${CLUSTER}/service-b:${TAG}"