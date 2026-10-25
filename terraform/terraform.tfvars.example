region             = "eu-west-1"
cluster_name       = "nginx-proxy-demo"
kubernetes_version = "1.37"
vpc_cidr           = "10.0.0.0/16"

node_instance_types = ["t3.medium"]
node_desired_size   = 3
node_min_size       = 2
node_max_size       = 4

# Élesben szűkítsd a saját IP-dre, pl. ["1.2.3.4/32"]
cluster_endpoint_public_access_cidrs = ["0.0.0.0/0"]