import boto3
import json
from botocore.exceptions import ClientError
import os
# Create Client
session = boto3.session.Session()
dynamoDbClient = session.client('dynamodb')
table_name = os.getenv('TABLE_NAME')

def lambda_handler(event,context):
    records = []
    response = {}
    try:
        # Get the first 1MB of data    
        response = dynamoDbClient.scan(
            TableName=table_name
        )
        if 'LastEvaluatedKey' in response:
            # Paginate returning up to 1MB of data for each iteration
            while 'LastEvaluatedKey' in response:
                response = dynamoDbClient.scan(
                    TableName=table_name,
                    ExclusiveStartKey=response['LastEvaluatedKey']
                )
                # Track number of Items read
                records = response['Items']

        else:
            records = response['Items']
        
        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": "application/json"
            },
            "body": json.dumps(records)
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