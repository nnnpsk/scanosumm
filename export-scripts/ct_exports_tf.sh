#!/bin/bash
# Deep CloudTrail → Terraform exporter (User-created only)
# Works on Git Bash (Windows) or Linux

OUTPUT_TF="cloudtrail.tf"
IMPORT_SCRIPT="ct_imports.sh"
VARIABLES_TF="variables.tf"

> "$OUTPUT_TF"
> "$IMPORT_SCRIPT"
> "$VARIABLES_TF"

echo "Starting CloudTrail deep export..."

ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# === Variables file ===
cat <<EOF > "$VARIABLES_TF"
variable "account_id" {
  description = "AWS Account ID"
  type        = string
  default     = "$ACCOUNT_ID"
}

variable "environment" {
  description = "Environment tag"
  type        = string
}

variable "project_name" {
  description = "Project tag"
  type        = string
}
EOF

sanitize_name() {
  echo "$1" | tr -cd '[:alnum:]_' | sed 's/^[_]*//'
}

# === Describe all trails ===
TRAILS_JSON=$(aws cloudtrail describe-trails --output json)
TRAILS=$(echo "$TRAILS_JSON" | grep '"Name":' | cut -d '"' -f4)

if [ -z "$TRAILS" ]; then
  echo "No CloudTrail trails found."
  exit 0
fi

for TRAIL in $TRAILS; do
  echo "Processing trail: $TRAIL"

  DETAILS=$(aws cloudtrail get-trail --name "$TRAIL" --output json)
  STATUS_INFO=$(aws cloudtrail get-trail-status --name "$TRAIL" --output json 2>/dev/null)

  IS_ORG=$(echo "$DETAILS" | grep -i '"IsOrganizationTrail": true')
  if [[ -n "$IS_ORG" ]]; then
    echo "Skipping organization-managed trail: $TRAIL"
    continue
  fi

  # Extract key fields
  NAME="$TRAIL"
  S3_BUCKET=$(echo "$DETAILS" | grep '"S3BucketName"' | cut -d '"' -f4)
  S3_KEY_PREFIX=$(echo "$DETAILS" | grep '"S3KeyPrefix"' | cut -d '"' -f4)
  LOG_GROUP_ARN=$(echo "$DETAILS" | grep '"CloudWatchLogsLogGroupArn"' | cut -d '"' -f4)
  LOG_ROLE_ARN=$(echo "$DETAILS" | grep '"CloudWatchLogsRoleArn"' | cut -d '"' -f4)
  INCLUDE_GLOBAL=$(echo "$DETAILS" | grep '"IncludeGlobalServiceEvents"' | grep -o 'true\|false')
  MULTI_REGION=$(echo "$DETAILS" | grep '"IsMultiRegionTrail"' | grep -o 'true\|false')
  VALIDATION=$(echo "$DETAILS" | grep '"LogFileValidationEnabled"' | grep -o 'true\|false')
  HOME_REGION=$(echo "$DETAILS" | grep '"HomeRegion"' | cut -d '"' -f4)
  HAS_ADV=$(echo "$DETAILS" | grep '"HasCustomEventSelectors"' | grep -o 'true\|false')
  HAS_INSIGHT=$(echo "$DETAILS" | grep '"HasInsightSelectors"' | grep -o 'true\|false')
  ARN=$(echo "$DETAILS" | grep '"TrailARN"' | cut -d '"' -f4)
  IS_LOGGING=$(echo "$STATUS_INFO" | grep '"IsLogging"' | grep -o 'true\|false')

  SAFE_NAME=$(sanitize_name "$NAME")

  # Replace account ID with var.account_id
  ARN_VAR=$(echo "$ARN" | sed "s/$ACCOUNT_ID/\${var.account_id}/g")
  LOG_ROLE_ARN_VAR=$(echo "$LOG_ROLE_ARN" | sed "s/$ACCOUNT_ID/\${var.account_id}/g")
  LOG_GROUP_ARN_VAR=$(echo "$LOG_GROUP_ARN" | sed "s/$ACCOUNT_ID/\${var.account_id}/g")

  # --- Write Terraform resource
  {
    echo "resource \"aws_cloudtrail\" \"$SAFE_NAME\" {"
    echo "  name                          = \"$NAME\""
    echo "  s3_bucket_name                = \"$S3_BUCKET\""
    [ -n "$S3_KEY_PREFIX" ] && echo "  s3_key_prefix                 = \"$S3_KEY_PREFIX\""
    [ -n "$LOG_GROUP_ARN_VAR" ] && echo "  cloud_watch_logs_group_arn    = \"$LOG_GROUP_ARN_VAR\""
    [ -n "$LOG_ROLE_ARN_VAR" ] && echo "  cloud_watch_logs_role_arn     = \"$LOG_ROLE_ARN_VAR\""
    echo "  include_global_service_events = $INCLUDE_GLOBAL"
    echo "  is_multi_region_trail         = $MULTI_REGION"
    echo "  enable_log_file_validation    = $VALIDATION"
    echo "  home_region                   = \"$HOME_REGION\""
    echo "  enable_logging                = $IS_LOGGING"
    echo "  is_organization_trail         = false"
    echo ""
    echo "  tags = {"
    echo "    Environment = var.environment"
    echo "    Project     = var.project_name"
    echo "  }"
    echo "}"
    echo ""
  } >> "$OUTPUT_TF"

  # --- Add import command
  echo "terraform import aws_cloudtrail.$SAFE_NAME $ARN_VAR" >> "$IMPORT_SCRIPT"

  # --- Optional sections
  if [[ "$HAS_ADV" == "true" ]]; then
    {
      echo "# NOTE: Trail '$NAME' includes advanced event selectors."
      echo "# Run: aws cloudtrail get-event-selectors --trail-name $NAME"
      echo ""
    } >> "$OUTPUT_TF"
  fi

  if [[ "$HAS_INSIGHT" == "true" ]]; then
    {
      echo "# NOTE: Trail '$NAME' includes insight selectors."
      echo "# Run: aws cloudtrail get-insight-selectors --trail-name $NAME"
      echo ""
    } >> "$OUTPUT_TF"
  fi
done