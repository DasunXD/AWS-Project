# 1. Get current AWS account details automatically
data "aws_caller_identity" "current" {}

# 2. Create an S3 Bucket to securely store the audit logs
resource "aws_s3_bucket" "sme_cloudtrail_bucket" {
  bucket_prefix = "sme-cloudtrail-logs-"
  force_destroy = true # This allows us to easily delete the bucket when testing is done
}

# 3. Add a Security Policy to the S3 bucket to allow CloudTrail to write logs
resource "aws_s3_bucket_policy" "cloudtrail_policy" {
  bucket = aws_s3_bucket.sme_cloudtrail_bucket.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.sme_cloudtrail_bucket.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.sme_cloudtrail_bucket.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      }
    ]
  })
}

# 4. Create the AWS CloudTrail for continuous security auditing (Zero Cost for 1st trail)
resource "aws_cloudtrail" "sme_audit_trail" {
  name                          = "sme-infrastructure-audit-trail"
  s3_bucket_name                = aws_s3_bucket.sme_cloudtrail_bucket.id
  include_global_service_events = false
  enable_logging                = true

  depends_on = [aws_s3_bucket_policy.cloudtrail_policy]
}
