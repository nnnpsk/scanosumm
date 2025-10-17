resource "aws_iam_role" "api_cw_log" {
  name = var.iam_api_cw_role
  description = "Allows API Gateway to push logs to CloudWatch Logs."
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
                "Service": "apigateway.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
POLICY
    tags = {
        Environment = var.environment
        Project     = var.project_name
    }
}

resource "aws_iam_role_policy_attachment" "AmazonAPIGatewayPushToCloudWatchLogs" {
  role       = aws_iam_role.api_cw_log.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}

resource "aws_iam_role" "lambda_infer_role" {
  name = var.lambda_infer_role
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "lambda.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
POLICY
    tags = {
        Environment = var.environment
        Project     = var.project_name
    }
}

resource "aws_iam_role_policy" "lambda_infer_lambda_invoke" {
  name   = var.lambda_invoke
  role   = aws_iam_role.lambda_infer_role.name
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.worker_lambda}"
        }
    ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "lambda_infer_brapikey" {
  role       = aws_iam_role.lambda_infer_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/${var.sm_br_policy}"
}

resource "aws_iam_role_policy_attachment" "lambda_infer_lambda_exec_role" {
  role       = aws_iam_role.lambda_infer_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/service-role/${var.lambda_exec_role}"
}

resource "aws_iam_role_policy_attachment" "lambda_infer_api" {
  role       = aws_iam_role.lambda_infer_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/${var.lambda_infer_api}"
}

resource "aws_iam_role_policy_attachment" "lambda_infer_s3" {
  role       = aws_iam_role.lambda_infer_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/${var.lambda_infer_s3}"
}

resource "aws_iam_role" "cw_br_role" {
  name = var.cw_br_role
  description = "Bedrock Access to CloudWatch Log Group"
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AmazonBedrockModelInvocationCWDeliveryRole",
            "Effect": "Allow",
            "Principal": {
                "Service": "bedrock.amazonaws.com"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "${var.account_id}"
                },
                "ArnLike": {
                    "aws:SourceArn": "arn:aws:bedrock:${var.aws_region}:${var.account_id}:*"
                }
            }
        }
    ]
}
POLICY
    tags = {
        Environment = var.environment
        Project     = var.project_name
    }
}

resource "aws_iam_role_policy_attachment" "cw_br_policy" {
  role       = aws_iam_role.cw_br_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/service-role/${var.cw_br_pol}"
}

resource "aws_iam_role" "cw_st_role" {
  name = var.cw_st_role
  description = "Role for config CloudWatchLogs for trail secretstrail"
  assume_role_policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudtrail.amazonaws.com"
            },
            "Action": "sts:AssumeRole",
            "Condition": {
                "StringEquals": {
                    "aws:SourceAccount": "${var.account_id}",
                    "aws:SourceArn": "arn:aws:cloudtrail:${var.aws_region}:${var.account_id}:trail/${var.sec_trails_name}"
                }
            }
        }
    ]
}
POLICY
    tags = {
        Environment = var.environment
        Project     = var.project_name
    }
}

resource "aws_iam_role_policy_attachment" "cw_st_policy" {
  role       = aws_iam_role.cw_st_role.name
  policy_arn = "arn:aws:iam::${var.account_id}:policy/service-role/${var.cw_st_pol}"
}

resource "aws_iam_policy" "lambda_infer_api" {
  name   = var.lambda_infer_api
  description = "Policy to provide access to the specific lambda upon firing"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "lambda:InvokeFunction",
            "Resource": "arn:aws:lambda:${var.aws_region}:${var.account_id}:function:${var.infer_lambda}"
        }
    ]
}
POLICY
    tags = {
        Environment = var.environment
        Project     = var.project_name
    }
}

resource "aws_iam_policy" "cw_br_pol" {
  name   = var.cw_br_pol
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AmazonBedrockModelInvocationCWDeliveryRole",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_lg_bedrock}:log-stream:${var.cw_ls_bedrock}"
        }
    ]
}
POLICY
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "s3-read" {
  name   = var.lambda_infer_s3
  description = "s3-read"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:ListBucket"
            ],
            "Resource": "arn:aws:s3:::${var.scanora_bucket_name}"
        },
        {
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:GetObject"
            ],
            "Resource": "arn:aws:s3:::${var.scanora_bucket_name}/*"
        }
    ]
}
POLICY
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "cw_st_pol" {
  name   = var.cw_st_pol
  description = "Policy for config CloudWathLogs for trail secretstrail"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AWSCloudTrailCreateLogStream2014110",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream"
            ],
            "Resource": [
                "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_lg_secretstrail}:log-stream:${var.account_id}_CloudTrail_${var.aws_region}*"
            ]
        },
        {
            "Sid": "AWSCloudTrailPutLogEvents20141101",
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_lg_secretstrail}:log-stream:${var.account_id}_CloudTrail_${var.aws_region}*"
            ]
        }
    ]
}
POLICY
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "sm_br_policy" {
  name   = var.sm_br_policy
  description  = "Policy to retrieve br-api-key"
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "secretsmanager:GetSecretValue",
            "Resource": "arn:aws:secretsmanager:${var.aws_region}:${var.account_id}:secret:${var.sm_secret}"
        }
    ]
}
POLICY
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}

resource "aws_iam_policy" "lambda_exec_role" {
  name   = var.lambda_exec_role
  policy = <<POLICY
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "logs:CreateLogGroup",
            "Resource": "arn:aws:logs:${var.aws_region}:${var.account_id}:*"
        },
        {
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogStream",
                "logs:PutLogEvents"
            ],
            "Resource": [
                "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_lg_infer}:*",
                "arn:aws:logs:${var.aws_region}:${var.account_id}:log-group:${var.cw_lg_worker}:*"
            ]
        }
    ]
}
POLICY
  tags = {
    Environment = var.environment
    Project     = var.project_name
  }
}
