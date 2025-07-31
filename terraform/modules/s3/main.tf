
resource "aws_s3_bucket" "image_storage" {
  bucket = "${var.project_name}-image-storage-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_public_access_block" "main" {
  bucket = aws_s3_bucket.image_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_cors_configuration" "main" {
  bucket = aws_s3_bucket.image_storage.id
  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["PUT", "POST", "GET"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "random_id" "bucket_suffix" {
  byte_length = 8
}
