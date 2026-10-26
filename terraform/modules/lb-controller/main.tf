locals {
  policy_file = "${path.module}/iam_policy.json"
}

# Trust policy (IRSA): a szerepet csak egy OIDC tokennel lehet felvenni, és csak akkor,
# ha a token a mi clusterünk kube-system/aws-load-balancer-controller ServiceAccountjáé
# (sub feltétel), és az STS-nek szól (aud feltétel). Más pod nem kapja meg ezeket a jogokat.
data "aws_iam_policy_document" "assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# IAM szerep a controllernek: ezzel hozza létre és kezeli az NLB-t, a target groupokat és a
# security group szabályokat.
resource "aws_iam_role" "this" {
  name               = "${var.cluster_name}-aws-lbc"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

# A controller hivatalos IAM policyja, a modul mellett lévő iam_policy.json fájlból.
resource "aws_iam_policy" "this" {
  name        = "${var.cluster_name}-AWSLoadBalancerControllerIAMPolicy"
  description = "AWS Load Balancer Controller (${var.cluster_name})"
  policy      = file(local.policy_file)

  # Védőháló: ha az iam_policy.json nem érvényes IAM policy (pl. üres, vagy valaki egy helyőrzőt
  # tett a helyére), a plan érthető hibaüzenettel álljon meg, ne az AWS API-tól jöjjön homályos hiba apply közben.
  lifecycle {
    precondition {
      condition     = can(jsondecode(file(local.policy_file)).Statement)
      error_message = "A modules/lb-controller/iam_policy.json nem érvényes IAM policy. Töltsd le a hivatalos policyt a controller verziójához illő verzióval (a 3.x óta a chart és a controller verziója megegyezik)."
    }
  }
}

# A policy csatolása a controller szerepéhez.
resource "aws_iam_role_policy_attachment" "this" {
  role       = aws_iam_role.this.name
  policy_arn = aws_iam_policy.this.arn
}

# Az AWS Load Balancer Controller telepítése Helm charttal (Helm provider 3.x: a set lista).
# A chart létrehozza a ServiceAccountot, és ráteszi a role-arn annotációt (IRSA). Az EKS egy
# webhookja ebből tudja, hogy a podba be kell tenni a ServiceAccount tokent és a szerep ARN-jét,
# amivel az AWS SDK felveszi a szerepet. (A webhook neve pod-identity-webhook, de ez az IRSA része,
# nem azonos az újabb "EKS Pod Identity" funkcióval.)
resource "helm_release" "this" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = var.chart_version
  namespace  = var.namespace

  set = [
    {
      name  = "clusterName"
      value = var.cluster_name
    },
    {
      name  = "region"
      value = var.region
    },
    {
      name  = "vpcId"
      value = var.vpc_id
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = var.service_account_name
    },
    {
      # A pontokat escape-elni kell, különben a Helm a kulcsot beágyazott útvonalnak venné
      name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
      value = aws_iam_role.this.arn
    },
  ]

  # A controller csak akkor induljon, ha a szerepén már rajta van a policy
  depends_on = [aws_iam_role_policy_attachment.this]
}
