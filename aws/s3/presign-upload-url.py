import boto3
import os
from datetime import datetime

# Get region from environment variable
region = os.environ.get('AWS_REGION', 'us-east-1')  # default fallback

# Create S3 client with region
s3 = boto3.client('s3', region_name=region)

# Get bucket from user
bucket = input("Enter S3 bucket name: ")

# Generate date prefix (yyyy/mm/dd/)
date_prefix = datetime.now().strftime('%Y/%m/%d/')

# Get key from user with prefilled date
try:
    import readline
    def prefill_input(prompt, prefill=''):
        readline.set_startup_hook(lambda: readline.insert_text(prefill))
        try:
            return input(prompt)
        finally:
            readline.set_startup_hook()
    
    key = prefill_input("Enter full key path (edit as needed): ", date_prefix)
except ImportError:
    # Fallback for systems without readline
    print(f"Key will be prefilled with: {date_prefix}")
    key_suffix = input("Enter file name to append (or full path to override): ")
    key = key_suffix if key_suffix.count('/') >= 2 else date_prefix + key_suffix

# Get local file path for curl command
local_file = input("Enter local file path for upload: ")

# Generate presigned URL
url = s3.generate_presigned_url(
    'put_object', 
    Params={'Bucket': bucket, 'Key': key}, 
    ExpiresIn=3600, 
    HttpMethod='PUT'
)

print(f"\nGenerated presigned URL:")
print(url)

print(f"\nCurl command to upload file:")
print(f'curl --location --retry 3 --retry-connrefused --request PUT --upload-file "{local_file}" "{url}"')

