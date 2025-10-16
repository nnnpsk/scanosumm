import boto3
import json
import os
import time
import uuid
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    raw_event = event
        
    body = raw_event.get("body", "")

    try:
        datai = json.loads(body)
    except json.JSONDecodeError:
        return {"statusCode": 400, "body": json.dumps({"error": "Invalid JSON in request body"})}

    print("Received event:", json.dumps(event, indent=2))

    # --- Constants ---
    region_name = os.environ["REGION_NAME"]
    bucket_name = os.environ["BUCKET_NAME"]
    folder_name_json = os.environ["JSON_FOLDER"]
    folder_name_resp = os.environ["RESP_FOLDER"]
    expiration = int(os.environ["EXPIRATION"])

    # --- File names ---
    timestamp = datetime.now().strftime('%y%m%d%H%M%S')
    uid = uuid.uuid4().hex[:8]
    input_filename = f"json_{timestamp}_{uid}.json"
    resp_filename = f"resp_{timestamp}_{uid}.html"
    local_input_file = f"/tmp/{input_filename}"
    html_output_file = f"/tmp/{resp_filename}"

    with open(local_input_file, "w") as f:
        json.dump(datai, f, indent=2)

    # --- Upload JSON input to S3 ---
    s3_client = boto3.client("s3")
    s3_key_json = f"{folder_name_json}/{input_filename}"

    s3_client.upload_file(
        Filename=local_input_file,
        Bucket=bucket_name,
        Key=s3_key_json,
        ExtraArgs={'ContentType': 'application/json'}
    )

    # --- Upload HTML to S3 ---
    html_content_dummy = """<!DOCTYPE html><html><head><meta charset="UTF-8"><title>Refresh</title><meta http-equiv="refresh" content="10"><style>body{margin:0;font:bold 16px Arial;padding:20px} .dots::after{content:'';animation:d 1.5s steps(4,end) infinite}@keyframes d{0%{content:''}25%{content:'.'}50%{content:'..'}75%{content:'...'}100%{content:''}}</style></head><body>Report is being generated. If it takes over a minute, close this page and contact the developer. This page refreshes every 10 seconds.<span class="dots"></span></body></html>"""
    with open(html_output_file, "w") as f:
        f.write(html_content_dummy)
    
    s3_key_html = f"{folder_name_resp}/{resp_filename}"
    s3_client.upload_file(
        Filename=html_output_file,
        Bucket=bucket_name,
        Key=s3_key_html,
        ExtraArgs={
            "CacheControl": "no-cache",  
            "ContentType": "text/html"   
        }
    )
    print(f"Uploaded Dummy HTML report to s3://{bucket_name}/{s3_key_html}")


    # --- Pre-signed URL for HTML output ---
    presigned_url = s3_client.generate_presigned_url(
        'get_object',
        Params={'Bucket': bucket_name, 'Key': s3_key_html},
        ExpiresIn=expiration
    )

    # --- Invoke Worker Lambda Asynchronously ---
    lambda_client = boto3.client('lambda')
    payload = {
        "bucket_name": bucket_name,
        "json_key": s3_key_json,
        "html_key": s3_key_html,
        "resp_filename": resp_filename,
        "input_filename": input_filename,
        "region_name": region_name
    }

    lambda_client.invoke(
        FunctionName=os.environ["WORKER_FUNCTION"],  
        InvocationType="Event",  # async
        Payload=json.dumps(payload)
    )

    # --- Clean up ---
    try:
        os.remove(local_input_file)
    except:
        pass

    # --- Return immediately to API Gateway ---
    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({
            "message": "Processing started. Report will be available shortly.",
            "download_url": presigned_url,
            "estimated_wait_seconds": 60
        })
    }