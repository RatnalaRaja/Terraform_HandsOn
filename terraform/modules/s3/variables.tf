# ./modules/s3/variables.tf
variable "bucket_name" {
  description = "The name for the S3 bucket."
  type        = string
}

variable "project_name" {
  description = "Name of the project to prefix resource names"
  type        = string
  default     = "upload-gallery-app"
}