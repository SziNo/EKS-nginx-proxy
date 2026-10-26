# Launch template a node-oknak. Azért kell, hogy a node-okra a SAJÁT node security groupunk
# kerüljön: launch template nélkül az EKS a saját, automatikusan létrehozott cluster SG-jét
# tenné rájuk, és a security-groups.tf szabályai (pl. az NLB forgalom) nem érvényesülnének.
# AMI-t és instance típust itt nem adunk meg: az AMI-t az EKS választja az ami_type alapján,
# az instance típus a node groupon van.
resource "aws_launch_template" "node" {
  name_prefix            = "${var.cluster_name}-node-"
  vpc_security_group_ids = [aws_security_group.node.id]

  metadata_options {
    http_endpoint = "enabled"
    # IMDSv2 kötelező: az instance metadata (és benne a node szerep ideiglenes kulcsai) csak
    # előzetesen kért tokennel olvasható. Ez véd az SSRF típusú támadások ellen, ahol egy
    # sebezhető alkalmazást rávesznek, hogy egyszerű GET kéréssel kiolvassa a metadatát.
    http_tokens = "required"
    # A token válasza legfeljebb 1 hálózati ugrást tehet meg. A normál podok saját hálózati
    # névtérben futnak, a node-hoz képest +1 ugrásra, ezért 1-es limitnél NEM érik el az IMDS-t,
    # így a node szerep kulcsait sem: minden podnak saját szerepe legyen (IRSA), vagy semmi.
    # A hostNetwork-ön futó rendszerpodok (pl. a VPC CNI) továbbra is elérik, nekik kell.
    # Az LB Controllernek nem kell IMDS: IRSA-t használ, a régiót és a vpcId-t a Helm értékekben kapja.
    http_put_response_hop_limit = 1
  }

  # Az EC2 konzolban legyen neve a node-oknak
  tag_specifications {
    resource_type = "instance"

    tags = {
      Name = "${var.cluster_name}-node"
    }
  }
}

# Managed node group: az EKS kezeli az EC2 instance-ok életciklusát (indítás, frissítés,
# leürítés). A node-ok a privát subnetekben futnak, 3 AZ-ban elosztva.
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "default"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.subnet_ids
  version         = aws_eks_cluster.this.version # a node-ok verziója kövesse a clusterét

  ami_type       = var.node_ami_type
  capacity_type  = "ON_DEMAND"
  instance_types = var.node_instance_types

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Frissítéskor egyszerre legfeljebb 1 node legyen nem elérhető (a DaemonSet nginx-ből így mindig marad)
  update_config {
    max_unavailable = 1
  }

  launch_template {
    id      = aws_launch_template.node.id
    version = aws_launch_template.node.latest_version
  }

  # - A node szerep policyjai nélkül a node-ok nem tudnának csatlakozni (és destroykor a
  #   policyk csak a node-ok után kerüljenek le).
  # - A vpc-cni és a kube-proxy addon legyen kész, mire a node-ok elindulnak.
  depends_on = [
    aws_iam_role_policy_attachment.node,
    aws_eks_addon.before_compute,
  ]
}
