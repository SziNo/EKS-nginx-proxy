locals {
  # A cluster OIDC kibocsátójának címe (https://oidc.eks.<régió>.amazonaws.com/id/<azonosító>).
  # Három helyen kell: a tanúsítvány lekérdezéséhez, az IAM OIDC providerhez és az outputhoz.
  oidc_issuer = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# Az EKS OIDC kibocsátójának TLS tanúsítványa: ebből vesszük az ujjlenyomatot (thumbprint).
data "tls_certificate" "oidc" {
  url = local.oidc_issuer
}

# IAM OIDC provider az IRSA-hoz (IAM Roles for Service Accounts): ezzel bízik meg az IAM a
# cluster által kiadott ServiceAccount tokenekben, így egy pod (pl. az LB Controller) saját
# IAM szerepet vehet fel ahelyett, hogy a node szerep jogait használná.
resource "aws_iam_openid_connect_provider" "this" {
  url             = local.oidc_issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}