# AWS Load Balancer Controller: IRSA szerep + Helm release. Ez hozza létre az NLB-t
# a k8s/nginx-service.yaml LoadBalancer Service-e alapján.
module "lb_controller" {
  source = "./modules/lb-controller"

  cluster_name      = module.eks.cluster_name
  region            = var.region
  vpc_id            = module.vpc.vpc_id
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url
  chart_version     = var.lb_controller_chart_version

  # A Helm release csak akkor induljon, ha az EKS modul MINDEN eleme kész: a node group
  # (különben a controller podjai nem tudnak elindulni) és az admin access entry
  # (különben a Helm provider nem jogosult telepíteni).
  depends_on = [module.eks]
}
