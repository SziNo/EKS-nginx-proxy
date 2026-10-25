#!/usr/bin/env bash
# Mindent lebont, a helyes sorrendben, és a végén ellenőrzi, hogy nem maradt-e
# fizetős erőforrás. Használat (a projekt gyökeréből): ./scripts/teardown.sh
set -euo pipefail

TF_DIR="terraform"
NAMESPACE="demo"

# A régiót és a cluster nevét a Terraform kimenetéből vesszük, mint a többi szkript.
# Ha nincs state (pl. már le van bontva), nincs mit tenni.
if ! REGION="$(terraform -chdir="$TF_DIR" output -raw region 2>/dev/null)"; then
  echo "Nincs Terraform kimenet (üres a state?). Valószínűleg már minden le van bontva."
  exit 0
fi
CLUSTER="$(terraform -chdir="$TF_DIR" output -raw cluster_name)"

echo "Régió: ${REGION}, cluster: ${CLUSTER}"

# ---------- 1. Kubernetes erőforrások: ELŐSZÖR, hogy a controller törölje az NLB-t ----------
# Az NLB-t nem a Terraform hozta létre, hanem az AWS Load Balancer Controller. Ha a cluster
# előbb tűnne el, az NLB gazdátlanul ott maradna, és a terraform destroy elakadna a VPC-n.
if aws eks describe-cluster --name "$CLUSTER" --region "$REGION" >/dev/null 2>&1; then
  aws eks update-kubeconfig --name "$CLUSTER" --region "$REGION" >/dev/null

  # --wait: a Service-en lévő controller finalizer miatt ez csak akkor tér vissza,
  # amikor a controller már törölte az NLB-t és a target groupokat.
kubectl delete -k k8s/base --ignore-not-found --wait=true --timeout=10m
else
  echo "A cluster már nem létezik, a Kubernetes lépés kimarad."
fi

# Biztonsági ellenőrzés: a controller az NLB-ket "k8s-<namespace>-..." névvel hozza létre.
echo "Várakozás, amíg a controller által létrehozott NLB eltűnik..."
for _ in $(seq 1 30); do
  LBS="$(aws elbv2 describe-load-balancers --region "$REGION" \
    --query "LoadBalancers[?starts_with(LoadBalancerName, 'k8s-${NAMESPACE}-')].LoadBalancerName" \
    --output text)"
  [ -z "$LBS" ] && break
  echo "  még létezik: ${LBS}"
  sleep 10
done
if [ -n "$LBS" ]; then
  echo "HIBA: az NLB 5 perc után is létezik (${LBS}). Nézd meg az EC2 konzolban, a destroy most elakadna."
  exit 1
fi

# ---------- 2. Terraform: minden más (EKS, VPC, NAT, ECR, IAM) ----------
# Szándékosan nincs -auto-approve: a Terraform megmutatja, mit töröl, és rákérdez.
terraform -chdir="$TF_DIR" destroy

# ---------- 3. Ellenőrzés: maradt-e fizetős erőforrás? ----------
echo
echo "Ellenőrzés (mindháromnál üres kimenet a jó):"
echo "- Load balancerek:"
aws elbv2 describe-load-balancers --region "$REGION" --query 'LoadBalancers[].LoadBalancerName' --output text
echo "- Futó NAT gatewayek:"
aws ec2 describe-nat-gateways --region "$REGION" --filter Name=state,Values=available \
  --query 'NatGateways[].NatGatewayId' --output text
echo "- EKS clusterek:"
aws eks list-clusters --region "$REGION" --query 'clusters' --output text
echo "Kész."