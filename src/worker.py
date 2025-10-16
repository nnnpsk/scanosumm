import boto3
import json
import os
import time
import traceback
from datetime import datetime
from botocore.exceptions import ClientError

def lambda_handler(event, context):
    print("Worker event:", json.dumps(event, indent=2))

    region_name = event["region_name"]
    bucket_name = event["bucket_name"]
    s3_key_json = event["json_key"]
    s3_key_html = event["html_key"]
    resp_filename = event["resp_filename"]

    folder_name_resp = os.environ["RESP_FOLDER"]
    folder_name_json = os.environ["JSON_FOLDER"]
    br_apikey = os.environ["BR_API_KEY"]
    current_year = datetime.now().year

    s3_client = boto3.client("s3", region_name=region_name)
    secrets_client = boto3.client("secretsmanager", region_name=region_name)

    # --- Get Secret ---
    start = time.time()
    secret_value = secrets_client.get_secret_value(SecretId=br_apikey)
    br_secret = json.loads(secret_value['SecretString'])[br_apikey]
    os.environ['AWS_BEARER_TOKEN_BEDROCK'] = br_secret
    print(f"Secrets fetch took {time.time() - start:.2f} seconds")

    # --- Download JSON ---
    local_json = f"/tmp/{os.path.basename(s3_key_json)}"
    s3_client.download_file(bucket_name, s3_key_json, local_json)

    with open(local_json, "r") as f:
        data = json.load(f)

    # --- Compute summary ---
    scanned_files = data.get("scannedFiles", [])
    features = data.get("features", [])
    total_unique_features = len(features)
    supported_features = sum(1 for f in features if f.get("supported", False))
    unsupported_features = total_unique_features - supported_features
    total_files_scanned = len(scanned_files)

    summary = {
        "total_files_scanned": total_files_scanned,
        "total_unique_features": total_unique_features,
        "supported_features": supported_features,
        "unsupported_features": unsupported_features
    }
    print(summary)

    # --- Prepare Bedrock call ---
    system_prompt = f"""
    You are an assistant that generates a complete HTML report for feature scans and browser compatibility.

    Your task is to:
    1. Parse the given JSON object to extract the following metrics:
    - Total number of scanned files (from `scannedFiles` array).
    - Total number of unique features (count of `featureId` in the `features` array).
    - Count of supported features (`supported: true`).
    - Count of unsupported features (`supported: false`).
    - For each supported and unsupported feature, count the number of `occurrences` and show in format: feature-name (count).
    - This count must be derived **programmatically**, not assumed.

    2. Generate a valid **self-contained HTML** report using the following structure and styling:

    ### HTML Structure:

    - Add a main header at the top, centered and underlined:  
    **Scanora - Feature Scan & Browser Compatibility Report**

    - Add a below section 
    **Section 1: Feature Scan Report**
    - Show a summary table:
        ------------------------------------------------------------  
        | Total Features | Supported | Unsupported | Files Scanned |  
        | {total_unique_features} | {supported_features}  | {unsupported_features} | {total_files_scanned} |  
        ------------------------------------------------------------  
    - Below the table:
        - List **Supported Features** as bullet points like:
        - feature-id (occurrence count of keyword of each unique feature-id)
        - List **Unsupported Features** as bullet points like:
        - feature-id (occurrence count of keyword of each unique feature-id)) — in **red color**

    - Add a visual divider:  
    `<hr>` or a `<div class="divider">` as defined in styles

    - Add a below section 
    **Section 2: Browser Compatibility Matrix**
    - Table with these columns:
        `Feature | Chrome | Chrome Android | Edge | Firefox | Firefox Android | Safari | Safari iOS`
    - Populate versions from the `versions` field of each supported feature
        - Show version numbers exactly as they are, including symbols such as ≤ and decimals. Use HTML entities for special characters like ≤ (use &le;) so they render correctly on web pages. Display version numbers in green using inline CSS or classes.
        - Show `"Not tracked"` in **red** for feature not tracked in baseline
        - Show `"Unsupported"` in **red** for unsupported versions

    - Below the matrix, show a warning box:
      Warning: Unsupported features may cause runtime or compatibility issues across certain browsers.

    - Add a footer:
    - Center-aligned
    - Smaller font
    - Text: © {current_year} Scanora

    ### Styling Rules (must be embedded in `<style>`):

    - Use Arial font.
    - `.version {{ color: green; font-weight: bold; }}` for supported versions
    - `.cross {{ color: red; font-weight: bold; }}` for unsupported or not tracked
    - `.warning` → yellow box with border, padding, dark yellow text
    - Tables: bordered, centered text, shaded header
    - Header `h1`: centered and underlined
    - `.divider {{ border-top: 3px solid #444; margin: 30px 0; }}`
    - `.footer {{ text-align: center; font-size: 12px; color: #555; margin-top: 40px; }}`

    ### Final Output Requirements:

    - Must start with: `<!DOCTYPE html><html><head>...</head><body>...</body></html>`
    - Must be valid standalone HTML
    - Do **not** return explanations or anything else outside the HTML

    ---

    JSON input will be provided next. Parse it and generate the complete HTML report.
    """
    user_prompt = "Use the file text and follow the system prompt."

    model_id = os.environ["BR_MODEL_ID"]
    client = boto3.client("bedrock-runtime", region_name=region_name)

    json_as_text = json.dumps(data, indent=2)
    messages = [
        {
            "role": "user",
            "content": [{
                "text": f"{system_prompt}\n\n{user_prompt}\n\n---\n{json_as_text}"
            }]
        }
    ]

    # --- Call Bedrock ---
    try:
        start = time.time()
        response = client.converse(
            modelId=model_id,
            messages=messages,
            inferenceConfig={"temperature": 0, "topP": 1, "maxTokens": 4096}
        )
        print(f"Bedrock call took {time.time() - start:.2f} seconds")

        reply_text = response['output']['message']['content'][0]['text']

    except Exception as e:
        print("Bedrock call failed:", str(e))
        traceback.print_exc()
        # --- Create fallback HTML content ---
        reply_text = """
        <html>
        <head><title>Internal Error</title></head>
        <body style="font-family: Arial; color: #444; text-align:center; margin-top:50px;">
            <h2>Internal error occurred</h2>
            <p>Please retry after an hour.</p>
        </body>
        </html>
        """

    html_output_file = f"/tmp/{resp_filename}"

    with open(html_output_file, "w", encoding="utf-8") as f:
        f.write(reply_text)

    # --- Upload HTML to S3 ---
    s3_client.upload_file(
        Filename=html_output_file,
        Bucket=bucket_name,
        Key=s3_key_html,
        ExtraArgs={'ContentType': 'text/html'}
    )
    print(f"Uploaded HTML report to s3://{bucket_name}/{s3_key_html}")

    # --- Cleanup ---
    try:
        os.remove(local_json)
        os.remove(html_output_file)
    except:
        pass

    return {"status": "completed", "html_s3_key": s3_key_html}