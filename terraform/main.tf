provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

# --- VPC Module ---
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

  private_dedicated_network_acl = true
  private_inbound_acl_rules = [
    { rule_number = 100, rule_action = "allow", from_port = 0, to_port = 0, protocol = "-1", cidr_block = "10.0.0.0/16" },
    { rule_number = 110, rule_action = "allow", from_port = 1024, to_port = 65535, protocol = "tcp", cidr_block = "0.0.0.0/0" }
  ]
  private_outbound_acl_rules = [
    { rule_number = 100, rule_action = "allow", from_port = 0, to_port = 0, protocol = "-1", cidr_block = "0.0.0.0/0" }
  ]
}

# --- S3 Module ---
module "s3" {
  source      = "./modules/s3"
  bucket_name = var.project_name
}

# --- THIS BLOCK NOW CREATES THE NODE GROUP'S IAM ROLE SEPARATELY ---
# This is the fix for the "NoSuchEntity" race condition.
# --- THIS BLOCK NOW CREATES THE NODE GROUP'S IAM ROLE SEPARATELY ---
# This is the fix for the "NoSuchEntity" race condition AND the trust policy.
resource "aws_iam_role" "eks_node_group" {
  name = "${var.project_name}-eks-node-group-role"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          # THIS IS THE FIX: Added "eks.amazonaws.com" to the list of trusted services.
          Service = [
            "ec2.amazonaws.com",
            "eks.amazonaws.com"
          ]
        },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "eks_node_group_worker_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_ecr_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_group.name
}

resource "aws_iam_role_policy_attachment" "eks_node_group_s3_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
  role       = aws_iam_role.eks_node_group.name
}


# --- EKS Module ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37.2"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  # This tells the module to create the role OUTSIDE, which we have now done.
  create_iam_role = false
  # This tells the node group to USE the role we created above.
  iam_role_arn    = aws_iam_role.eks_node_group.arn

  eks_managed_node_groups = {
    default_node_group = {
      desired_size = 2
      max_size     = 3
      min_size     = 1

      instance_types = ["t3.medium"]
      
      # We now pass the ARN directly to the node group definition
      iam_role_arn = aws_iam_role.eks_node_group.arn
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
      protocol    = "tcp"
      from_port   = 443
      to_port     = 443
      type        = "ingress"
      cidr_blocks = [module.vpc.vpc_cidr_block]
    }
  }
}

# --- IAM Module for IRSA ---
# NOTE: This module is currently commented out to simplify the deployment.
# You can add this back after the cluster is successfully created.
# module "iam" {
#   source                   = "./modules/iam"
#   project_name             = var.project_name
#   s3_bucket_arn            = module.s3.bucket_arn
#   oidc_provider_arn        = module.eks.oidc_provider_arn
#   oidc_provider_url        = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
#   k8s_namespace            = "gallery-app"
#   k8s_service_account_name = "gallery-sa"
# }

# --- Helm Provider and Release ---
# NOTE: These are also commented out. You can add these back after the cluster is created.
# provider "helm" {
#   kubernetes {
#     host                   = module.eks.cluster_endpoint
#     cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
#     exec {
#       api_version = "client.authentication.k8s.io/v1beta1"
#       command     = "aws"
#       args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
#     }
#   }
# }
#
# resource "helm_release" "aws_load_balancer_controller" {
#   name       = "aws-load-balancer-controller"
#   repository = "https://aws.github.io/eks-charts"
#   chart      = "aws-load-balancer-controller"
#   namespace  = "kube-system"
#
#   set { name  = "clusterName", value = module.eks.cluster_name }
#   set { name  = "serviceAccount.create", value = "true" }
#   set { name  = "serviceAccount.name", value = "aws-load-balancer-controller" }
# }

# --- Admin Role for EKS access ---
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
