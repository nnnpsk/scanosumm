resource "aws_wafv2_web_acl" "wafv2_web_acl_scanora_webacl" {
  name  = var.waf_webacl_name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.waf_webacl_name
    sampled_requests_enabled   = true
  }

  rule {
    name     = var.waf_metric_name
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_limit 
        aggregate_key_type    = "${var.waf_agg_type}"
        evaluation_window_sec = var.waf_eval_window
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = var.waf_metric_name
      sampled_requests_enabled   = true
    }
  }

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }


  lifecycle {
    ignore_changes = [rule]
  }
}
