module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = "${var.project}-eks"
  cluster_version = var.cluster_version

  vpc_id = module.vpc.vpc_id

  # Nodes go in public subnets (no NAT gateway); control-plane ENIs stay private.
  subnet_ids               = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access       = true
  cluster_endpoint_public_access_cidrs = var.api_allowed_cidrs

  # Gives the IAM identity running terraform cluster-admin via an EKS access entry
  enable_cluster_creator_admin_permissions = true

  # Cost trimming: a customer-managed KMS key is $1/month and CloudWatch log
  # ingestion is billed. (EKS still encrypts Kubernetes API data at rest by default.)
  create_kms_key              = false
  cluster_encryption_config   = {}
  create_cloudwatch_log_group = false
  cluster_enabled_log_types   = []

  cluster_addons = {
    coredns                = { most_recent = true }
    kube-proxy             = { most_recent = true }
    vpc-cni                = { most_recent = true, before_compute = true }
    eks-pod-identity-agent = { most_recent = true }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = startswith(var.node_instance_type, "t4g") ? "AL2023_ARM_64_STANDARD" : "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      min_size       = var.node_min_size
      desired_size   = var.node_desired_size
      max_size       = var.node_max_size
    }
  }
}

# ECR PULL ACCESS
# The module's managed node group IAM role automatically gets the AWS-managed
# AmazonEC2ContainerRegistryReadOnly policy, so the nodes (kubelet) can pull from
# any ECR repo in this account. Pods need no imagePullSecrets for ECR images.
