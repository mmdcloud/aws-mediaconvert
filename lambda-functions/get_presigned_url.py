import boto3
import json

def lambda_handler(event, context):
    print(event)
    s3_client = boto3.client(
        's3',
        region_name='us-east-1'
    )
    body = json.loads(event['body'])
    url = s3_client.generate_presigned_url(
        ClientMethod='put_object',
        Params={'Bucket': 'mediaconvertsrcmadmax', 'Key': body["file"],'Metadata': {
            "record_name": body["file"]
        }},
        ExpiresIn=60,
    )
    return url