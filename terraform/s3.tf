################################################################################
# S3 Bucket - Terraform State
################################################################################

module "s3_tfstate" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.14.1"

  bucket = "${local.resource_name}-tfstate"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning = {
    enabled = true
  }

  tags = var.tags
}

################################################################################
# S3 Bucket - Application Data
################################################################################

module "s3_data" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.14.1"

  bucket = "${local.resource_name}-data"

  control_object_ownership = true
  object_ownership         = "BucketOwnerEnforced"

  force_destroy = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  versioning = {
    enabled = true
  }

  tags = var.tags
}
