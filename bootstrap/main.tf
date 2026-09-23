# The shared Terraform state backend.
#
# Applied ONCE, by hand, before any other project's `terraform init`. Every repo
# then points at this bucket with its own key — one bucket to secure, version and
# audit instead of one per project.
#
# Locking is S3-native (`use_lockfile = true` in the consumer's backend block), so
# there is no DynamoDB table here. That option landed in Terraform 1.10 and made
# the DynamoDB lock table obsolete; keeping one now is cargo cult.

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "state" {
  bucket = var.bucket_name

  # State is the source of truth for every environment. Losing it is worse than
  # losing the infrastructure, because you lose the ability to manage what's left.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# A KMS CMK rather than SSE-S3: state files contain resource attributes and
# occasionally secrets, and a CMK means access can be revoked independently of
# the bucket policy.
resource "aws_kms_key" "state" {
  description             = "Encrypts Terraform state in ${var.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.state.key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-noncurrent-state"
    status = "Enabled"

    filter {}

    # Old versions are the undo button, but they are not free and not needed
    # forever.
    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

# Refuse any request that did not arrive over TLS. Without this the bucket policy
# permits plaintext HTTP, which would put state on the wire in clear.
data "aws_iam_policy_document" "state" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyUnencryptedObjectUploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json
}
