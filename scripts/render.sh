#!/usr/bin/env bash
# Kitölti a k8s/kustomization.yaml és a Service annotáció helyőrzőit a Terraform kimenetéből.
# Használat: ./scripts/render.sh 1.0.0
set -euo pipefail

TAG="${1:-1.0.0}"
REGION="$(terraform -chdir=terraform output -raw region)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SG_ID="$(terraform -chdir=terraform output -raw nlb_security_group_id)"

sed -i \
  -e "s/ACCOUNT_ID/${ACCOUNT_ID}/g" \
  -e "s/REGION/${REGION}/g" \
  -e "s/newTag: \".*\"/newTag: \"${TAG}\"/g" \
  k8s/kustomization.yaml

sed -i -e "s/NLB_SG_ID/${SG_ID}/" k8s/nginx-service.yaml

echo "Kitöltve. Ellenőrzés: kubectl kustomize k8s/"
