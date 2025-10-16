resource "aws_cloudwatch_log_group" "scanora" {
  name = var.cw_lg_apigw
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "welcome" {
  name = var.cw_lg_welcome
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "bedrock_model" {
  name = var.cw_lg_bedrock
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "infer_lambda" {
  name = var.cw_lg_infer
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "worker_lambda" {
  name = var.cw_lg_worker
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "sec_trail" {
  name = var.cw_lg_secretstrail
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "api_gateway_exec_logs" {
  name = "${var.cw_api_lg}/prod"
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_cloudwatch_log_group" "waf_logs" {
  name = var.cw_lg_waf
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
