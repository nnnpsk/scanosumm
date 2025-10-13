#!/usr/bin/env bash
set -euo pipefail

### export_s3_tf.sh
### Deep-ish export of S3 resources to Terraform (human readable)
### Produces: s3.tf, variables.tf, s3_imports.sh
### Run in Git Bash or Linux (requires aws CLI configured)

OUT_TF="s3.tf"
IMPORT_SH="s3_imports.sh"
VAR_TF="variables.tf"

# reset files
> "${OUT_TF}"
> "${IMPORT_SH}"
> "${VAR_TF}"

echo "Starting S3 export -> ${OUT_TF}, import helper -> ${IMPORT_SH}"

# account id
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# variables.tf
cat > "${VAR_TF}" <<EOF
variable "account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "$ACCOUNT_ID"
}

variable "environment" {
  description = "Environment (e.g. dev, prod)"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "myproject"
}
EOF

# helper to make Terraform-safe resource names
sanitize() {
  # keep letters, numbers and underscores; convert others to _
  echo "$1" | sed 's/[^a-zA-Z0-9]/_/g' | sed 's/^_*\(.*\)_*$/\1/'
}

# pattern list of buckets to skip (adjustable)
skip_bucket() {
  local b="$1"
  # skip buckets that are clearly AWS-managed (adjust these patterns)
  case "$b" in
    aws-*|*.elasticbeanstalk.com|aws-cloudtrail-*|*elasticbeanstalk*|*_logs|*lambda*|*awsexample*)
    # aws-*|*.elasticbeanstalk.com|aws-cloudtrail-*|*elasticbeanstalk*|*_logs|*lambda*|*awsexample*)
      return 0 ;; # skip
    *)
      return 1 ;;
  esac
}

# list all buckets
BUCKETS=$(aws s3api list-buckets --query "Buckets[].Name" --output text)

if [[ -z "${BUCKETS// /}" ]]; then
  echo "No S3 buckets found or AWS CLI/profile not configured."
  exit 0
fi

# header for s3.tf
cat >> "${OUT_TF}" <<'EOF'
# AUTO-GENERATED s3.tf
# Review before importing/applying.
# Contains: aws_s3_bucket, bucket policy, encryption, versioning, logging, public access block
#
# Tags are set from variables: var.environment, var.project_name
#
EOF

# loop
for BUCKET in $BUCKETS; do
  if skip_bucket "$BUCKET"; then
    echo "Skipping bucket (pattern): $BUCKET"
    continue
  fi

  echo "Processing bucket: $BUCKET"

  SAFE=$(sanitize "$BUCKET")
  # bucket resource
  cat >> "${OUT_TF}" <<EOF

### Bucket: ${BUCKET}
resource "aws_s3_bucket" "${SAFE}" {
  bucket = "${BUCKET}"
  # acl and other properties intentionally omitted to avoid accidental drift
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
EOF

  # import command for bucket
  echo "terraform import aws_s3_bucket.${SAFE} ${BUCKET}" >> "${IMPORT_SH}"

  #
  # Bucket tagging (explicit tags resource optional) -> fetch tags and add comment if user-created tags exist
  #
  if aws s3api get-bucket-tagging --bucket "${BUCKET}" >/dev/null 2>&1; then
    TAGS_JSON=$(aws s3api get-bucket-tagging --bucket "${BUCKET}" --output json 2>/dev/null || echo "")
    if [[ -n "$TAGS_JSON" ]]; then
      # write tags as data comment so user can inspect (we already added tags variable block)
      cat >> "${OUT_TF}" <<EOF

# Existing tags for ${BUCKET} (review and merge as desired):
# ${TAGS_JSON}
EOF
    fi
  fi

  #
  # Bucket policy
  #
  if aws s3api get-bucket-policy --bucket "${BUCKET}" >/dev/null 2>&1; then
    echo "  exporting bucket policy"
    POL=$(aws s3api get-bucket-policy --bucket "${BUCKET}" --query Policy --output text)
    # substitute account id occurrences with var.account_id
    POL_VAR=$(echo "$POL" | sed "s/${ACCOUNT_ID}/\${var.account_id}/g")
    cat >> "${OUT_TF}" <<EOF

resource "aws_s3_bucket_policy" "${SAFE}_policy" {
  bucket = aws_s3_bucket.${SAFE}.id
  policy = <<POLICY
${POL_VAR}
POLICY
}
EOF
    echo "terraform import aws_s3_bucket_policy.${SAFE}_policy ${BUCKET}" >> "${IMPORT_SH}"
  fi

  #
  # Server-side encryption (SSE)
  #
  SSE_ALGO=$(aws s3api get-bucket-encryption --bucket "${BUCKET}" --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" --output text 2>/dev/null || echo "")
  SSE_KMS=$(aws s3api get-bucket-encryption --bucket "${BUCKET}" --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.KMSMasterKeyID" --output text 2>/dev/null || echo "")
  SSE_BUCKET_KEY=$(aws s3api get-bucket-encryption --bucket "${BUCKET}" --query "ServerSideEncryptionConfiguration.Rules[0].BucketKeyEnabled" --output text 2>/dev/null || echo "")

  if [[ -n "$SSE_ALGO" && "$SSE_ALGO" != "None" ]]; then
    echo "  exporting SSE ($SSE_ALGO)"
    # convert KMS key arn to var.account_id if present
    if [[ -n "$SSE_KMS" ]]; then
      SSE_KMS_VAR=$(echo "$SSE_KMS" | sed "s/${ACCOUNT_ID}/\${var.account_id}/g")
    fi

    # write resource
    cat >> "${OUT_TF}" <<EOF

resource "aws_s3_bucket_server_side_encryption_configuration" "${SAFE}_encryption" {
  bucket = aws_s3_bucket.${SAFE}.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "${SSE_ALGO}"
$( [[ -n "$SSE_KMS_VAR" ]] && echo "      kms_master_key_id = \"${SSE_KMS_VAR}\"" || true )
    }
$( [[ "$SSE_BUCKET_KEY" == "true" ]] && echo "    bucket_key_enabled = true" || true )
  }
}
EOF
    echo "terraform import aws_s3_bucket_server_side_encryption_configuration.${SAFE}_encryption ${BUCKET}" >> "${IMPORT_SH}"
  fi

  #
  # Versioning
  #
  VER_STATUS=$(aws s3api get-bucket-versioning --bucket "${BUCKET}" --query Status --output text 2>/dev/null || echo "")
  if [[ -n "$VER_STATUS" && "$VER_STATUS" != "None" ]]; then
    echo "  exporting versioning ($VER_STATUS)"
    cat >> "${OUT_TF}" <<EOF

resource "aws_s3_bucket_versioning" "${SAFE}_versioning" {
  bucket = aws_s3_bucket.${SAFE}.id

  versioning_configuration {
    status = "${VER_STATUS}"
  }
}
EOF
    echo "terraform import aws_s3_bucket_versioning.${SAFE}_versioning ${BUCKET}" >> "${IMPORT_SH}"
  fi

  #
  # Logging
  #
  LOGGING_JSON=$(aws s3api get-bucket-logging --bucket "${BUCKET}" --output json 2>/dev/null || echo "")
  if [[ "$LOGGING_JSON" != "" && "$LOGGING_JSON" != "{}" ]]; then
    TARGET_BUCKET=$(echo "$LOGGING_JSON" | sed -n 's/.*"TargetBucket":"\([^"]*\)".*/\1/p' || true)
    TARGET_PREFIX=$(echo "$LOGGING_JSON" | sed -n 's/.*"TargetPrefix":"\([^"]*\)".*/\1/p' || true)
    if [[ -n "$TARGET_BUCKET" ]]; then
      # replace account ids in target bucket ARN if any (usually not)
      cat >> "${OUT_TF}" <<EOF

resource "aws_s3_bucket_logging" "${SAFE}_logging" {
  bucket = aws_s3_bucket.${SAFE}.id
  target_bucket = "${TARGET_BUCKET}"
  target_prefix = "${TARGET_PREFIX}"
}
EOF
      echo "terraform import aws_s3_bucket_logging.${SAFE}_logging ${BUCKET}" >> "${IMPORT_SH}"
    fi
  fi

  #
  # Public access block
  #
  if aws s3api get-public-access-block --bucket "${BUCKET}" >/dev/null 2>&1; then
    echo "  exporting public access block"
    # read each flag
    B1=$(aws s3api get-public-access-block --bucket "${BUCKET}" --query "PublicAccessBlockConfiguration.BlockPublicAcls" --output text 2>/dev/null || echo "false")
    B2=$(aws s3api get-public-access-block --bucket "${BUCKET}" --query "PublicAccessBlockConfiguration.IgnorePublicAcls" --output text 2>/dev/null || echo "false")
    B3=$(aws s3api get-public-access-block --bucket "${BUCKET}" --query "PublicAccessBlockConfiguration.BlockPublicPolicy" --output text 2>/dev/null || echo "false")
    B4=$(aws s3api get-public-access-block --bucket "${BUCKET}" --query "PublicAccessBlockConfiguration.RestrictPublicBuckets" --output text 2>/dev/null || echo "false")

    cat >> "${OUT_TF}" <<EOF

resource "aws_s3_bucket_public_access_block" "${SAFE}_public_access_block" {
  bucket = aws_s3_bucket.${SAFE}.id

  block_public_acls   = ${B1}
  ignore_public_acls  = ${B2}
  block_public_policy = ${B3}
  restrict_public_buckets = ${B4}
}
EOF
    echo "terraform import aws_s3_bucket_public_access_block.${SAFE}_public_access_block ${BUCKET}" >> "${IMPORT_SH}"
  fi

  #
  # Object lock configuration (if enabled)
  #
  if aws s3api get-object-lock-configuration --bucket "${BUCKET}" >/dev/null 2>&1; then
    echo "  exporting object lock configuration"
    OBJ_LOCK_JSON=$(aws s3api get-object-lock-configuration --bucket "${BUCKET}" --output json)
    cat >> "${OUT_TF}" <<EOF

# Note: object lock configuration for ${BUCKET} (raw JSON shown for review)
# ${OBJ_LOCK_JSON}
resource "aws_s3_bucket_object_lock_configuration" "${SAFE}_object_lock" {
  bucket = aws_s3_bucket.${SAFE}.id
  # review above JSON and map to HCL if you want a strict resource.
}
EOF
    # import command: resource expects bucket name
    echo "terraform import aws_s3_bucket_object_lock_configuration.${SAFE}_object_lock ${BUCKET}" >> "${IMPORT_SH}"
  fi

  #
  # CORS, lifecycle, replication, website, analytics etc. — export raw JSON as comments for review
  #
  # CORS
  if aws s3api get-bucket-cors --bucket "${BUCKET}" >/dev/null 2>&1; then
    CORS_JSON=$(aws s3api get-bucket-cors --bucket "${BUCKET}" --output json)
    cat >> "${OUT_TF}" <<EOF

# Bucket CORS for ${BUCKET} (raw JSON — convert to aws_s3_bucket_cors_configuration manually if desired)
# ${CORS_JSON}
EOF
  fi

  # Lifecycle
  if aws s3api get-bucket-lifecycle-configuration --bucket "${BUCKET}" >/dev/null 2>&1; then
    LIFECYCLE_JSON=$(aws s3api get-bucket-lifecycle-configuration --bucket "${BUCKET}" --output json)
    cat >> "${OUT_TF}" <<EOF

# Bucket lifecycle for ${BUCKET} (raw JSON — convert to aws_s3_bucket_lifecycle_configuration manually if desired)
# ${LIFECYCLE_JSON}
EOF
  fi

  # Replication
  if aws s3api get-bucket-replication --bucket "${BUCKET}" >/dev/null 2>&1; then
    REPL_JSON=$(aws s3api get-bucket-replication --bucket "${BUCKET}" --output json)
    cat >> "${OUT_TF}" <<EOF

# Bucket replication for ${BUCKET} (raw JSON — convert to aws_s3_bucket_replication_configuration manually if desired)
# ${REPL_JSON}
EOF
  fi

  # Website
  if aws s3api get-bucket-website --bucket "${BUCKET}" >/dev/null 2>&1; then
    WEB_JSON=$(aws s3api get-bucket-website --bucket "${BUCKET}" --output json)
    cat >> "${OUT_TF}" <<EOF

# Bucket website configuration for ${BUCKET} (raw JSON — convert to aws_s3_bucket_website_configuration manually if desired)
# ${WEB_JSON}
EOF
  fi

done