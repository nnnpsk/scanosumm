resource "aws_s3_bucket" "aws_cloudtrail_logs" {
  bucket = var.ct_bucket_name

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_s3_bucket_policy" "aws_cloudtrail_logs_policy" {
  bucket = aws_s3_bucket.aws_cloudtrail_logs.id
  policy = <<POLICY
{"Version":"2012-10-17","Statement":[{"Sid":"AWSCloudTrailAclCheck20150319-4d4588a5-b636-4e66-8ffd-5fb17f92fe3a","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:GetBucketAcl","Resource":"arn:aws:s3:::${var.ct_bucket_name}","Condition":{"StringEquals":{"AWS:SourceArn":"arn:aws:cloudtrail:${var.aws_region}:${var.account_id}:trail/${var.sec_trails_name}"}}},{"Sid":"AWSCloudTrailWrite20150319-e7b5868c-c49b-493b-a9ea-1bc9fbeb2b9b","Effect":"Allow","Principal":{"Service":"cloudtrail.amazonaws.com"},"Action":"s3:PutObject","Resource":"arn:aws:s3:::${var.ct_bucket_name}/AWSLogs/${var.account_id}/*","Condition":{"StringEquals":{"AWS:SourceArn":"arn:aws:cloudtrail:${var.aws_region}:${var.account_id}:trail/${var.sec_trails_name}","s3:x-amz-acl":"bucket-owner-full-control"}}}]}
POLICY
}

resource "aws_s3_bucket_server_side_encryption_configuration" "aws_cloudtrail_logs_encryption" {
  bucket = aws_s3_bucket.aws_cloudtrail_logs.id

  rule {
    bucket_key_enabled = false

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      kms_master_key_id = var.kms_master_key_id
    }

  }
}

resource "aws_s3_bucket_public_access_block" "aws_cloudtrail_logs_public_access_block" {
  bucket = aws_s3_bucket.aws_cloudtrail_logs.id

  block_public_acls   = true
  ignore_public_acls  = true
  block_public_policy = true
  restrict_public_buckets = true
}


resource "aws_s3_bucket" "scanora_bucket" {
  bucket = var.scanora_bucket_name

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

# Create prefix 
resource "aws_s3_object" "json_prefix" {
  bucket = aws_s3_bucket.scanora_bucket.id
  key    = "${var.s3_json_folder}/"     # trailing slash 
  content = ""                # empty object
  cache_control = "max-age=0"
}

# Create prefix 
resource "aws_s3_object" "html_prefix" {
  bucket = aws_s3_bucket.scanora_bucket.id
  key    = "${var.s3_resp_folder}/" 
  content = ""
  cache_control = "max-age=0"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "scanora_bucket_encryption" {
  bucket = aws_s3_bucket.scanora_bucket.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
      kms_master_key_id = var.kms_master_key_id
    }

  }
}

resource "aws_s3_bucket_versioning" "scanora_bucket_versioning" {
  bucket = aws_s3_bucket.scanora_bucket.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "scanora_bucket_public_access_block" {
  bucket = aws_s3_bucket.scanora_bucket.id

  block_public_acls   = true
  ignore_public_acls  = true
  block_public_policy = true
  restrict_public_buckets = true
}
