# WebFeatures Scan: Claude-Powered Browser Compatibility Reporter

This repository contains Terraform and Lambda code used to extend the Scanora web feature scan tool with an automated HTML compatibility report generator driven by large models hosted via AWS Bedrock (example: Anthropic Claude via Bedrock).

This README explains the repository layout, the purpose of every Terraform file and, the export helper scripts (how they were created and how to use them, if needed)

## Repository

- `terraform/` — Terraform configuration  
  - `main.tf` — Terraform provider information (AWS provider and required versions).
  - `apigateway.tf` — API Gateway (REST API v1) resources: REST API, resource path, methods, integration to `infer` Lambda, model and request validator, usage plan and API key, stage + access logging.
  - `lambda.tf` — Lambda function resources and lambda permission for API Gateway invocation. Creates two primary functions: `infer` and `worker`.
  - `s3.tf` — S3 buckets used by Scanora (CloudTrail bucket and a `scanora` bucket for inputs and HTML outputs). Creates prefixes for JSON and HTML folders and configures encryption/versioning/public access block.
  - `iam.tf` — IAM roles and policies needed for API Gateway, Bedrock, CloudWatch, Secrets Manager, S3 and Lambda execution policies.
  - `cloudwatch.tf` — CloudWatch Log Groups used by API Gateway, Lambdas, Bedrock, WAF and other services.
  - `cloudtrail.tf` — CloudTrail trail that writes to an S3 bucket 
  - `bedrock.tf` — AWS Bedrock guardrail config (content filters / policy enforcement for model inputs/outputs).
  - `sm.tf` — Secrets Manager secret resource for storing the Bedrock API key. 
  - `waf.tf` — WAF to protect the API
  - `variables.tf` — List of variables used by the Terraform code
  - `src/` — Lambda code and sample payload
    - `infer.py` / `infer.zip` — receives requests from the Scanora scan json report, uploads JSON + placeholder HTML to S3, returns a presigned URL, and invokes `worker` asynchronously
    - `worker.py` / `worker.zip` — reads JSON from S3, calls Bedrock to build the HTML report, uploads final HTML to S3
      
- `exports/` — helper scripts to export existing AWS resources into Terraform + import commands
  - These helper scripts scans the AWS account and produce Terraform HCL fragments and its corresponding `terraform import`; Note: These scripts were created using `Kiro` and `ChatGPT` to speed things up,as the infra was created via console.

## Why run `terraform import`

If AWS resources already exist, Terraform does not know about them until imported. `terraform import` links an existing resource to the Terraform resource name in the code. This keeps Terraform state and real infra in sync and stops Terraform from trying to recreate resources.

Sample import steps, Replace names/ARNs with actual values:

```
cd terraform
terraform init

# example imports
terraform import aws_s3_bucket.scanora_bucket my-scanora-bucket
terraform import aws_lambda_function.lambda_scanora_infer arn:aws:lambda:us-east-1:123456789012:function:lambda-infer
terraform import aws_api_gateway_rest_api.scanorarestapi a1b2c3d4
terraform import aws_secretsmanager_secret.sm_br_api_key arn:aws:secretsmanager:us-east-1:123456789012:secret:my-br-secret
```

After import, run `terraform plan` to see differences. Edit HCL if needed and run following as needed to apply the changes(with `.tfvars` updated)

`terraform plan -out=tfplan`  
`terraform apply "tfplan"`

## Lambdas — detailed behavior

**1)** infer Lambda (`terraform/src/infer.py`)
- Receives POST from API Gateway(from Scanora-Webfeatures scan tool). Expects JSON body describing a scan (payload example available in `terraform/src/scanresultmodel.json`).
- Persist JSON to S3 under `${JSON_FOLDER}/json_<timestamp>_<id>.json`.
- Uploads a small placeholder HTML file to `${RESP_FOLDER}/resp_<timestamp>_<id>.html` that auto-refreshes, so callers can poll a link while processing continues.
- Generates a presigned GET URL for the HTML object and returns it to the requester (fast response).
- Asynchronously invokes the worker Lambda with S3 keys and metadata.

**2)** worker Lambda (`terraform/src/worker.py`)
- Downloads the JSON file from S3 and computes a small numeric summary (counts, supported/unsupported features).
- Fetches the Bedrock API key from Secrets Manager (the code expects the secret to contain an object where the key is the secret name).
- Prepares a system-style prompt that instructs the model to generate a complete, self-contained HTML report (tables, compatibility matrix, coloring, warnings, footer, etc.).
- Calls `bedrock-runtime` Converse API (`client.converse`) with the chosen model (provided via `BR_MODEL_ID` environment variable).
- Writes the resulting HTML to a temp file and uploads it to S3 (replacing the placeholder page uploaded earlier).
- In case of any errors/exception an Internal error occured page will be resulted in the web page.
