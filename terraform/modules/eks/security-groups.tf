# FONTOS: a szabályok külön erőforrások (aws_vpc_security_group_ingress_rule / egress_rule),
# nem inline ingress/egress blokkok. Inline blokkoknál a Terraform a security group ÖSSZES
# szabályát kezelné, és a következő apply törölné azokat, amelyeket az AWS Load Balancer
# Controller vesz fel a node SG-be (manage-backend-security-group-rules).

locals {
  # A NodePort tartomány. Ide érkezik az NLB forgalma (target-type: instance), és az
  # externalTrafficPolicy: Local miatt a health check is (a healthCheckNodePort is ebből a tartományból van).
  node_port_from = 30000
  node_port_to   = 32767

  # A control plane által a node-okon/podokon elért portok (név => port)
  cluster_to_node_ports = {
    https       = 443   # pl. a control plane webhookjai a 443-on figyelő podok felé
    kubelet     = 10250 # kubectl logs/exec, a kubelet API
    lbc_webhook = 9443  # AWS Load Balancer Controller webhook: enélkül a LoadBalancer Service létrehozása hibára fut
  }
}

# Kiegészítő security group a control plane ENI-khez (az EKS ezen felül egy saját
# "cluster security groupot" is létrehoz automatikusan).
resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster"
  description = "EKS control plane (additional)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.cluster_name}-cluster"
  }
}

# Security group a node-oknak (a launch template rakja rájuk). A kubernetes.io/cluster tag
# alapján találja meg az AWS Load Balancer Controller azt a SG-t, amelybe a saját szabályait felveszi.
resource "aws_security_group" "node" {
  name        = "${var.cluster_name}-node"
  description = "EKS managed node group"
  vpc_id      = var.vpc_id

  tags = {
    Name                                        = "${var.cluster_name}-node"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

# Security group az NLB-nek (a feladat kéri). A k8s/nginx-service.yaml annotációjában adjuk át
# a controllernek (a scripts/render.sh tölti ki az nlb_security_group_id outputból).
resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-nlb"
  description = "Public NLB in front of the nginx DaemonSet"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.cluster_name}-nlb"
  }
}

# --- Cluster SG szabályok ---

# A node-ok elérhetik a Kubernetes API-t (443) a privát endpointon.
resource "aws_vpc_security_group_ingress_rule" "cluster_from_nodes_https" {
  security_group_id            = aws_security_group.cluster.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  description                  = "Kubernetes API from nodes"
}

# A control plane kifelé bárhová kapcsolódhat (kubelet, webhookok a node-okon).
resource "aws_vpc_security_group_egress_rule" "cluster_all" {
  security_group_id = aws_security_group.cluster.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# --- Node SG szabályok ---

# Node-node és pod-pod forgalom: a VPC CNI miatt a podok a node ENI-jein kapnak IP-t, így ez a SG
# vonatkozik rájuk is (pl. nginx -> service-a pod másik node-on, CoreDNS lekérdezések).
resource "aws_vpc_security_group_ingress_rule" "node_self" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "-1"
  description                  = "Node to node and pod to pod"
}

# A control plane elérheti a node-okat a szükséges portokon (lásd local.cluster_to_node_ports).
resource "aws_vpc_security_group_ingress_rule" "node_from_cluster" {
  for_each = local.cluster_to_node_ports

  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.cluster.id
  ip_protocol                  = "tcp"
  from_port                    = each.value
  to_port                      = each.value
  description                  = "From control plane: ${each.key}"
}

# Az NLB elérheti a node-okat a NodePort tartományon: az nginx Service NodePortja
# ÉS a health check (healthCheckNodePort) is itt van (Hints: "NLB health checks").
# A controller (manage-backend-security-group-rules) is felvesz egy szabályt, ez a
# Terraformos szabály akkor is biztosítja az elérést, ha az valamiért nem jönne létre.
resource "aws_vpc_security_group_ingress_rule" "node_from_nlb" {
  security_group_id            = aws_security_group.node.id
  referenced_security_group_id = aws_security_group.nlb.id
  ip_protocol                  = "tcp"
  from_port                    = local.node_port_from
  to_port                      = local.node_port_to
  description                  = "NodePort traffic and health checks from NLB"
}

# A node-ok kifelé bárhová kapcsolódhatnak (ECR, EKS API, S3 – a NAT gatewayen át).
resource "aws_vpc_security_group_egress_rule" "node_all" {
  security_group_id = aws_security_group.node.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All outbound"
}

# --- NLB SG szabályok ---

# HTTP az internetről (vagy a megadott tartományokból) az NLB 80-as portjára.
resource "aws_vpc_security_group_ingress_rule" "nlb_http" {
  for_each = toset(var.nlb_ingress_cidrs)

  security_group_id = aws_security_group.nlb.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP from ${each.value}"
}

# Az NLB csak a node-ok NodePort tartományára küldhet (forgalom + health check).
resource "aws_vpc_security_group_egress_rule" "nlb_to_nodes" {
  security_group_id            = aws_security_group.nlb.id
  referenced_security_group_id = aws_security_group.node.id
  ip_protocol                  = "tcp"
  from_port                    = local.node_port_from
  to_port                      = local.node_port_to
  description                  = "To nodes: NodePort traffic and health checks"
}
