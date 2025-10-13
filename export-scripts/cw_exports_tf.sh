#!/bin/bash
# Deep AWS CloudWatch export to Terraform (no jq, region: us-east-1 only)
# Exports log groups, retention, kms_key_id, and tags

OUTPUT_TF="cloudwatch.tf"
IMPORT_SCRIPT="cw_imports.sh"
VARIABLES_TF="variables.tf"
REGION="us-east-1"

> "$OUTPUT_TF"
> "$IMPORT_SCRIPT"
> "$VARIABLES_TF"

echo "Starting CloudWatch export for region: $REGION"

# Get current AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# === variables.tf ===
cat <<EOF > "$VARIABLES_TF"
variable "account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "$ACCOUNT_ID"
}

variable "environment" {
  description = "Environment tag"
  type        = string
  default     = "prod"
}

variable "project_name" {
  description = "Project name tag"
  type        = string
  default     = "scanora"
}
EOF

# === Helper: Sanitize Terraform resource names ===
sanitize_name() {
  echo "$1" | tr -cd '[:alnum:]_' | sed 's/^[_]*//'
}

# === Fetch all log groups ===
mkdir -p .cloudwatch_export_tmp
FILE=".cloudwatch_export_tmp/log_groups_${REGION}.json"

echo "Fetching CloudWatch log groups from $REGION..."
aws logs describe-log-groups --region "$REGION" --output json > "$FILE" 2>/dev/null

if ! grep -q "logGroupName" "$FILE"; then
  echo "No log groups found in $REGION or invalid output."
  exit 0
fi

LOG_GROUPS=$(grep -o '"logGroupName": *"[^"]*"' "$FILE" | cut -d '"' -f4)

# === Loop through each log group ===
for GROUP in $LOG_GROUPS; do
  SAFE_NAME=$(sanitize_name "$GROUP")
  echo "Exporting log group: $GROUP"

  RETENTION=$(grep -A3 "\"logGroupName\": *\"$GROUP\"" "$FILE" | grep '"retentionInDays"' | awk -F': ' '{print $2}' | tr -d ', ')
  KMS_KEY=$(grep -A3 "\"logGroupName\": *\"$GROUP\"" "$FILE" | grep '"kmsKeyId"' | cut -d '"' -f4)

  {
    echo "resource \"aws_cloudwatch_log_group\" \"$SAFE_NAME\" {"
    echo "  name = \"$GROUP\""
    [ -n "$RETENTION" ] && echo "  retention_in_days = $RETENTION"
    [ -n "$KMS_KEY" ] && echo "  kms_key_id        = \"$KMS_KEY\""
    echo "  tags = {"
    echo "    Environment = var.environment"
    echo "    Project     = var.project_name"
    echo "  }"
    echo "}"
    echo ""
  } >> "$OUTPUT_TF"

  echo "terraform import aws_cloudwatch_log_group.$SAFE_NAME $GROUP" >> "$IMPORT_SCRIPT"
done