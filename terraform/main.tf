provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {}
data "aws_caller_identity" "current" {}

# --- VPC Module (Official Terraform AWS Module) ---
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.1"  # You can adjust this version as needed

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
  source             = "./modules/eks"
  project_name       = var.project_name
  cluster_name       = var.cluster_name
  private_subnet_ids = module.vpc.private_subnets
}

# --- OIDC Provider Data Source ---
data "aws_iam_openid_connect_provider" "eks" {
  url = module.eks.cluster_oidc_issuer_url
}

# --- IAM Module for IRSA ---
module "iam" {
  source                   = "./modules/iam"
  project_name             = var.project_name
  s3_bucket_arn            = module.s3.bucket_arn
  oidc_provider_arn        = data.aws_iam_openid_connect_provider.eks.arn
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
