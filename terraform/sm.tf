resource "aws_secretsmanager_secret" "sm_br_api_key" {
  name                    = var.sm_br_api_key
  description             = "api key for aws bedrock for scanora project"

  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
