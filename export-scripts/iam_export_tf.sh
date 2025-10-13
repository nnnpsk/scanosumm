#!/bin/bash
# Deep AWS IAM export to Terraform (human-readable version)
# Compatible with Git Bash / Linux
# Exports: Roles, Trust Policies, Inline Policies, Managed Attachments, Custom Managed Policies
# Skips AWS-managed roles/policies and uses account_id variable

OUTPUT_TF="iam.tf"
IMPORT_SCRIPT="iam_imports.sh"
VARIABLES_TF="variables.tf"

> "$OUTPUT_TF"
> "$IMPORT_SCRIPT"
> "$VARIABLES_TF"

echo "Exporting IAM configuration to Terraform (human-readable)..."

# Get current account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)

# Create variables.tf
cat <<EOF > "$VARIABLES_TF"
variable "account_id" {
  description = "AWS Account ID for IAM resources"
  type        = string
  default     = "$ACCOUNT_ID"
}
EOF

# Helper to sanitize Terraform resource names
sanitize_name() {
  echo "$1" | tr -cd '[:alnum:]_' | sed 's/^[_]*//'
}

# ===Export IAM Roles ===
ROLES=$(aws iam list-roles --query "Roles[].RoleName" --output text)

for ROLE in $ROLES; do
  ROLE_PATH=$(aws iam get-role --role-name "$ROLE" --query "Role.Path" --output text)
  
  # Skip AWS service roles
  if [[ "$ROLE" == AWSServiceRoleFor* ]] || [[ "$ROLE_PATH" == *"aws-service-role/"* ]]; then
    echo "Skipping AWS-managed role: $ROLE"
    continue
  fi

  SAFE_ROLE=$(sanitize_name "$ROLE")
  echo "Exporting role: $ROLE"

  TRUST_POLICY=$(aws iam get-role --role-name "$ROLE" \
    --query "Role.AssumeRolePolicyDocument" --output json)

  {
    echo "resource \"aws_iam_role\" \"$SAFE_ROLE\" {"
    echo "  name = \"$ROLE\""
    echo "  assume_role_policy = <<POLICY"
    echo "$TRUST_POLICY"
    echo "POLICY"
    echo "}"
    echo ""
  } >> "$OUTPUT_TF"

  echo "terraform import aws_iam_role.$SAFE_ROLE $ROLE" >> "$IMPORT_SCRIPT"

  # === Inline Policies ===
  INLINE_POLICIES=$(aws iam list-role-policies --role-name "$ROLE" \
    --query "PolicyNames[]" --output text)

  for POL in $INLINE_POLICIES; do
    SAFE_POL=$(sanitize_name "${SAFE_ROLE}_${POL}")
    POLICY_DOC=$(aws iam get-role-policy --role-name "$ROLE" \
      --policy-name "$POL" --query "PolicyDocument" --output json)

    {
      echo "resource \"aws_iam_role_policy\" \"$SAFE_POL\" {"
      echo "  name   = \"$POL\""
      echo "  role   = aws_iam_role.$SAFE_ROLE.name"
      echo "  policy = <<POLICY"
      echo "$POLICY_DOC"
      echo "POLICY"
      echo "}"
      echo ""
    } >> "$OUTPUT_TF"

    echo "terraform import aws_iam_role_policy.$SAFE_POL ${ROLE}:${POL}" >> "$IMPORT_SCRIPT"
  done

  # === Attached Managed Policies ===
  ATTACHED=$(aws iam list-attached-role-policies --role-name "$ROLE" \
    --query "AttachedPolicies[].PolicyArn" --output text)

  for ARN in $ATTACHED; do
    [ -z "$ARN" ] && continue
    ARN_WITH_VAR=$(echo "$ARN" | sed "s/$ACCOUNT_ID/\${var.account_id}/g")
    POLICY_NAME=$(basename "$ARN")
    SAFE_ATTACH=$(sanitize_name "${SAFE_ROLE}_${POLICY_NAME}")

    {
      echo "resource \"aws_iam_role_policy_attachment\" \"$SAFE_ATTACH\" {"
      echo "  role       = aws_iam_role.$SAFE_ROLE.name"
      echo "  policy_arn = \"$ARN_WITH_VAR\""
      echo "}"
      echo ""
    } >> "$OUTPUT_TF"

    echo "terraform import aws_iam_role_policy_attachment.$SAFE_ATTACH ${ROLE}/${ARN}" >> "$IMPORT_SCRIPT"
  done
done

# === Export Custom Managed Policies ===
echo "Scanning custom (Local) managed IAM policies..."
POLICIES=$(aws iam list-policies --scope Local --query "Policies[].Arn" --output text)

for ARN in $POLICIES; do
  NAME=$(aws iam get-policy --policy-arn "$ARN" --query "Policy.PolicyName" --output text)
  VERSION=$(aws iam get-policy --policy-arn "$ARN" --query "Policy.DefaultVersionId" --output text)
  DOC=$(aws iam get-policy-version --policy-arn "$ARN" --version-id "$VERSION" \
    --query "PolicyVersion.Document" --output json)

  SAFE_NAME=$(sanitize_name "$NAME")
  ARN_WITH_VAR=$(echo "$ARN" | sed "s/$ACCOUNT_ID/\${var.account_id}/g")

  {
    echo "resource \"aws_iam_policy\" \"$SAFE_NAME\" {"
    echo "  name   = \"$NAME\""
    echo "  policy = <<POLICY"
    echo "$DOC"
    echo "POLICY"
    echo "}"
    echo ""
  } >> "$OUTPUT_TF"

  echo "terraform import aws_iam_policy.$SAFE_NAME $ARN_WITH_VAR" >> "$IMPORT_SCRIPT"
done
