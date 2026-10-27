#!/usr/bin/env bash
# Legenerálja a helyi overlay-t (k8s/overlays/local/kustomization.yaml) a Terraform
# kimenetéből. A base (k8s/base/) érintetlen marad, ezért a szkript akárhányszor futtatható.
# Használat: ./scripts/render.sh 1.0.0
set -euo pipefail

TAG="${1:-1.0.0}"
REGION="$(terraform -chdir=terraform output -raw region)"
CLUSTER="$(terraform -chdir=terraform output -raw cluster_name)"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
SG_ID="$(terraform -chdir=terraform output -raw nlb_security_group_id)"
# A repók címe: <regiszter>/<cluster_name>/<szolgáltatás>
REPO_BASE="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${CLUSTER}"

OVERLAY_DIR="k8s/overlays/local"
mkdir -p "$OVERLAY_DIR"

# A "cat >" minden futtatáskor teljesen felülírja a fájlt, így mindig az aktuális
# értékek kerülnek bele. A heredoc-ban a bash behelyettesíti a ${...} változókat.
cat > "${OVERLAY_DIR}/kustomization.yaml" <<EOF
# GENERÁLT FÁJL, ne szerkeszd kézzel: a scripts/render.sh írja. Nincs a gitben.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# A közös manifestek, környezetfüggő érték nélkül
resources:
- ../../base

# Az "image: service-a" és "image: service-b" cseréje az ECR címre és a tagre.
# A "name" a Deploymentben lévő image névre illeszkedik, ezért az nem változik.
images:
- name: service-a
  newName: ${REPO_BASE}/service-a
  newTag: "${TAG}"
- name: service-b
  newName: ${REPO_BASE}/service-b
  newTag: "${TAG}"

# Az NLB security group ID beírása a Service annotációjába (strategic merge patch).
# Az ID minden terraform apply után más, ezért nem lehet a base-ben.
patches:
- target:
    kind: Service
    name: nginx-proxy
  patch: |-
    apiVersion: v1
    kind: Service
    metadata:
      name: nginx-proxy
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-security-groups: ${SG_ID}
EOF

echo "Generálva: ${OVERLAY_DIR}/kustomization.yaml (tag: ${TAG}, SG: ${SG_ID})"
echo "Ellenőrzés: kubectl kustomize ${OVERLAY_DIR}"