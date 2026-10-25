# Saját security group az NLB-nek (a feladat kéri). A Service annotációban adjuk át,
# az AWS Load Balancer Controller pedig a node SG-be felveszi a szükséges bejövő szabályt.
resource "aws_security_group" "nlb" {
  name        = "${var.cluster_name}-nlb"
  description = "Public NLB in front of the nginx DaemonSet"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "To the nodes (NodePort + health check)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }
}
