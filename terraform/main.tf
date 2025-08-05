provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

# --- VPC Module ---
# This part is correct and builds your network.
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"

  name = var.project_name
  cidr = "10.0.0.0/16"

  azs             = slice(data.aws_availability_zones.available.names, 0, 2)
  private_subnets = ["10.0.101.0/24", "10.0.102.0/24"]
  public_subnets  = ["10.0.1.0/24", "10.0.2.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false

  # This creates the NACL rules to allow your runner to connect.
  private_dedicated_network_acl = true
  private_inbound_acl_rules = [
    { rule_number = 100, rule_action = "allow", from_port = 0, to_port = 0, protocol = "-1", cidr_block = "10.0.0.0/16" },
    { rule_number = 110, rule_action = "allow", from_port = 1024, to_port = 65535, protocol = "tcp", cidr_block = "0.0.0.0/0" }
  ]
  private_outbound_acl_rules = [
    { rule_number = 100, rule_action = "allow", from_port = 0, to_port = 0, protocol = "-1", cidr_block = "0.0.0.0/0" }
  ]
}

# --- EKS Module ---
# This part is correct and builds your EKS cluster and nodes.
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37.2"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  eks_managed_node_groups = {
    default_node_group = {
      desired_size = 2, max_size = 3, min_size = 1
      instance_types = ["t3.medium"]
    }
  }

  access_entries = {
    admin = {
      kubernetes_groups = ["eks-admin"]
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AdminRole"
    }
  }

  cluster_security_group_additional_rules = {
    vpc_internal_https_access = {
      description = "Allow internal VPC traffic to EKS API for self-hosted runners"
      protocol    = "tcp", from_port = 443, to_port = 443, type = "ingress"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
}

# --- This block creates the Admin Role for EKS access ---
resource "aws_iam_role" "admin" {
  name = "AdminRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.admin.name
}

# NOTE: The S3, IAM for IRSA, Helm Provider, and Helm Release blocks have been removed for simplicity.
# They can be added back one by one after the cluster is successfully created.
