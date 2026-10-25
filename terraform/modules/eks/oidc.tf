# Az EKS OIDC kibocsátójának TLS tanúsítványa: ebből vesszük az ujjlenyomatot (thumbprint).
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

# IAM OIDC provider az IRSA-hoz (IAM Roles for Service Accounts): ezzel bízik meg az IAM a
# cluster által kiadott ServiceAccount tokenekben, így egy pod (pl. az LB Controller) saját
# IAM szerepet vehet fel ahelyett, hogy a node szerep jogait használná.
resource "aws_iam_openid_connect_provider" "this" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}
