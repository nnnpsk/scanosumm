resource "aws_api_gateway_rest_api" "scanorarestapi" {
  name = var.api_gateway
  
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_api_gateway_resource" "scanorarestapi_scan" {
  rest_api_id = aws_api_gateway_rest_api.scanorarestapi.id
  parent_id   = aws_api_gateway_rest_api.scanorarestapi.root_resource_id
  path_part   = var.pathpart
}

resource "aws_api_gateway_method" "scanorarestapi_scan_POST" {
  rest_api_id = aws_api_gateway_rest_api.scanorarestapi.id
  resource_id = aws_api_gateway_resource.scanorarestapi_scan.id
  http_method = "POST"
  authorization = "NONE"
  api_key_required = true

  # Add request models mapping back
  request_models = {
    "application/json" = var.req_model
  }

  # Reattach request validator (must exist)
  request_validator_id = aws_api_gateway_request_validator.validate_body.id

}

resource "aws_api_gateway_integration" "scanorarestapi_scan_POST_int" {
  rest_api_id = aws_api_gateway_rest_api.scanorarestapi.id
  resource_id = aws_api_gateway_resource.scanorarestapi_scan.id
  http_method = aws_api_gateway_method.scanorarestapi_scan_POST.http_method
  content_handling        = "CONVERT_TO_TEXT"
  integration_http_method = "POST"
  type = "AWS_PROXY"
  uri = "arn:aws:apigateway:${var.aws_region}:lambda:path/2015-03-31/functions/arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.infer_lambda}/invocations"
}

resource "aws_api_gateway_deployment" "deploy_7p0hf2" {
  rest_api_id = aws_api_gateway_rest_api.scanorarestapi.id
}


resource "aws_api_gateway_stage" "prod" {
  stage_name = "prod"
  rest_api_id = aws_api_gateway_rest_api.scanorarestapi.id
  deployment_id = aws_api_gateway_deployment.deploy_7p0hf2.id

    access_log_settings {
    destination_arn = "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_api_lg}/prod"
    format          = jsonencode({
      requestId               = "$context.requestId"
      ip                      = "$context.identity.sourceIp"
      caller                  = "$context.identity.caller"
      user                    = "$context.identity.user"
      requestTime             = "$context.requestTime"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      status                  = "$context.status"
      protocol                = "$context.protocol"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
    })
  }
  tags = {
    Environment = var.environment
    Project     = var.project_name
  } 
}

resource "aws_api_gateway_model" "scanresultmodel" {
  rest_api_id  = aws_api_gateway_rest_api.scanorarestapi.id
  name         = var.req_model
  description  = "Model to validate scan request payloads"
  content_type = "application/json"

  # Load JSON schema from external file
  schema = file("${path.module}/src/${var.req_model}.json")
}

resource "aws_api_gateway_request_validator" "validate_body" {
  name                        = "validate-body"
  rest_api_id                 = aws_api_gateway_rest_api.scanorarestapi.id
  validate_request_body       = true
  validate_request_parameters = false
}

resource "aws_api_gateway_usage_plan" "scanora_client_plan" {
  name        = var.usage_plan_name
  description = "Client usage plan for Scanora API"

  api_stages {
    api_id = aws_api_gateway_rest_api.scanorarestapi.id
    stage  = aws_api_gateway_stage.prod.stage_name
  }

  throttle_settings {
    burst_limit = var.burst_limit     # burst
    rate_limit  = var.rate_limit      # requests per second
  }

  quota_settings {
    limit  = var.quota_limit         # quota count
    period = var.quota_period
  }
}

###############################################
# API Key
###############################################
resource "aws_api_gateway_api_key" "scanora_client_key" {
  name      = var.apikey_name 
  enabled   = true
}

###############################################
# Link Key → Usage Plan
###############################################
resource "aws_api_gateway_usage_plan_key" "scanora_client_plan_key" {
  key_id        = aws_api_gateway_api_key.scanora_client_key.id
  key_type      = "API_KEY"
  usage_plan_id = aws_api_gateway_usage_plan.scanora_client_plan.id
}
