import boto3
import json
import os

src_bucket = os.getenv('SRC_BUCKET') 
region = os.getenv('REGION')
def lambda_handler(event, context):
    try:
        print(event)
        s3_client = boto3.client(
            's3',
            region_name=region
        )
        body = json.loads(event['body'])
        url = s3_client.generate_presigned_url(
            ClientMethod='put_object',
            Params={'Bucket':src_bucket, 'Key': body["file"],'Metadata': {
                "record_name": body["file"]
            }},
            ExpiresIn=60,
        )
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "url": url
            })
        }
    except Exception as e:
        print(f"Error generating presigned URL: {e}")
        return {
            "statusCode": 500,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps({
                "error": str(e)
            })
        }