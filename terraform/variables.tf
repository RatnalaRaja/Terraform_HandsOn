variable "aws_region" {
  description = "The AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1" # Or any default region you prefer
}

variable "project_name" {
  description = "The unique name for the project, used for naming resources."
  type        = string
}

variable "cluster_name" {
  description = "The name for the EKS cluster."
  type        = string
}