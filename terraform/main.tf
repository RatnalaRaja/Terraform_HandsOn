provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

# --- VPC Module (Official Terraform AWS Module) ---
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

  tags = {
    "kubernetes.io/cluster/${var.project_name}-eks" = "shared"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# --- S3 Module ---
module "s3" {
  source      = "./modules/s3"
  bucket_name = var.project_name
}

# --- EKS Module ---
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.37.2"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  eks_managed_node_groups = {
    default_node_group = {
      desired_size = 2
      max_size     = 3
      min_size     = 1

      instance_types = ["t3.medium"]

      iam_role_additional_policies = {
        S3Access = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
      }
    }
  }

  access_entries = {
    admin = {
      kubernetes_groups = ["eks-admin"]
      principal_arn     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/AdminRole"
    }
  }

  # --- ADDED THIS BLOCK TO PREVENT THE HELM TIMEOUT ERROR ---
  # This rule allows the GitHub Actions runner to connect to the cluster's public API.
  cluster_security_group_additional_rules = {
    github_actions_https_access = {
      description      = "Allow GitHub Actions Runner to connect to EKS API"
      protocol         = "tcp"
      from_port        = 443
      to_port          = 443
      type             = "ingress"
      cidr_blocks      = ["0.0.0.0/0"]
    }
  }
}

# --- IAM Module for IRSA ---
module "iam" {
  source                   = "./modules/iam"
  project_name             = var.project_name
  s3_bucket_arn            = module.s3.bucket_arn
  oidc_provider_arn        = module.eks.oidc_provider_arn
  oidc_provider_url        = replace(module.eks.cluster_oidc_issuer_url, "https://", "")
  k8s_namespace            = "gallery-app"
  k8s_service_account_name = "gallery-sa"
}

# --- Helm Provider for EKS ---
provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
}

# --- AWS Load Balancer Controller Helm Chart ---
resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}


# --- ADDED this block to create the Admin Role for EKS access ---
resource "aws_iam_role" "admin" {
  name = "AdminRole"

  assume_role_policy = jsonencode({
    Version   = "2012-10-17",
    Statement = [
      {
        Effect    = "Allow",
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        },
        Action    = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "admin_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.admin.name
}
