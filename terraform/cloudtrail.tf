resource "aws_cloudtrail" "secrets_trail" {
  name                          = var.sec_trails_name
  s3_bucket_name                = var.ct_bucket_name
  cloud_watch_logs_group_arn    = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_secret_lg}"
  cloud_watch_logs_role_arn     = "arn:aws:iam::${var.account_id}:role/service-role/${var.cw_lg_role}"
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = false
  enable_logging                = false
  is_organization_trail         = false

  # Advanced event selectors
  advanced_event_selector {
    name = "Management events selector"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
