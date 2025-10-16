resource "aws_lambda_function" "lambda_scanora_worker" {
  function_name = var.worker_lambda
  role = "arn:aws:iam::${var.account_id}:role/service-role/${var.iam_lambda_role}"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.13"
  timeout = 300
  memory_size = 1024
  filename = "src/worker.zip"
  source_code_hash = filebase64sha256("src/worker.zip")
  description = "Worker Lambda for Scanora"

  environment {
    variables = {
      BR_API_KEY = var.sm_br_api_key
      BR_MODEL_ID = var.br_model
      JSON_FOLDER = var.s3_json_folder
      RESP_FOLDER = var.s3_resp_folder
    }
  }
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_lambda_function" "lambda_scanora_infer" {
  function_name = var.infer_lambda
  role = "arn:aws:iam::${var.account_id}:role/service-role/${var.iam_lambda_role}"
  handler = "lambda_function.lambda_handler"
  runtime = "python3.13"
  timeout = 60
  memory_size = 1024
  filename = "src/infer.zip"
  source_code_hash = filebase64sha256("src/infer.zip")
  description = "Inference Lambda for Scanora"

    environment {
    variables = {
      BUCKET_NAME = var.scanora_bucket_name
      REGION_NAME = var.aws_region
      JSON_FOLDER = var.s3_json_folder
      RESP_FOLDER = var.s3_resp_folder
      WORKER_FUNCTION = var.worker_lambda
      EXPIRATION = var.s3_presigned_expiry
    }
  }
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
 
}

# Allow API Gateway to invoke a Lambda function
resource "aws_lambda_permission" "apigw_invoke" {
statement_id = var.gw_invoke_id
action = "lambda:InvokeFunction"
function_name = aws_lambda_function.lambda_scanora_infer.function_name
principal = "apigateway.amazonaws.com"

# ex: arn:aws:execute-api:<region>:<account_id>:<api_id>/*/*/*
source_arn = "arn:aws:execute-api:${var.aws_region}:${var.account_id}:${var.api_id}/*/POST/${var.pathpart}"
}
