locals {
  # Addonok, amelyek a node-ok ELŐTT települnek: a vpc-cni nélkül a node-ok nem lesznek Ready-k
  addons_before_compute = toset(["vpc-cni", "kube-proxy"])
  # Addonok, amelyek a node-ok UTÁN települnek: a CoreDNS podjainak node kell, különben
  # az addon DEGRADED állapotban várna, és a Terraform kb. 20 perc után timeoutolna
  addons_after_compute = toset(["coredns"])
}

# Az adott Kubernetes verzióhoz elérhető legújabb addon verzió lekérdezése (addononként).
# A var.kubernetes_version-t használja (nem a clusterét), így már a plan kiírja a verziókat,
# és ha valamelyik addon nem érhető el ehhez a verzióhoz, a plan azonnal hibát ad.
data "aws_eks_addon_version" "this" {
  for_each = setunion(local.addons_before_compute, local.addons_after_compute)

  addon_name         = each.key
  kubernetes_version = var.kubernetes_version
  most_recent        = true
}

# EKS managed addonok a node group előtt: vpc-cni (pod hálózat) és kube-proxy (Service szabályok).
# Az OVERWRITE felülírja az EKS által alapból telepített, nem managed változatot.
resource "aws_eks_addon" "before_compute" {
  for_each = local.addons_before_compute

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

# EKS managed addon a node group után: coredns (cluster DNS, ezzel oldja fel az nginx a
# service-a.demo.svc.cluster.local neveket).
resource "aws_eks_addon" "after_compute" {
  for_each = local.addons_after_compute

  cluster_name                = aws_eks_cluster.this.name
  addon_name                  = each.key
  addon_version               = data.aws_eks_addon_version.this[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  depends_on = [aws_eks_node_group.this]
}
