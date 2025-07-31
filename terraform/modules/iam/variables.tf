# ./modules/iam/variables.tf

variable "project_name" {
  description = "A name for the project to prefix resources."
  type        = string
}

variable "s3_bucket_arn" {
  description = "The ARN of the S3 bucket the role needs access to."
  type        = string
}

variable "oidc_provider_arn" {
  description = "The ARN of the EKS OIDC identity provider."
  type        = string
}

variable "oidc_provider_url" {
  description = "The URL of the OIDC identity provider, without the 'https://' prefix."
  type        = string
}

variable "k8s_namespace" {
  description = "The Kubernetes namespace where the service account resides."
  type        = string
}

variable "k8s_service_account_name" {
  description = "The name of the Kubernetes service account to grant permissions."
  type        = string
}