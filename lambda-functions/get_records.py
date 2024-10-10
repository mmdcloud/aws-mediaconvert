import boto3

# Function to paginate through items
def lambda_handler(event, context):
    dynamodb = boto3.client('dynamodb')
    data = [];
    statusCode = 200
    table = dynamodb.Table('records')
    try:
        response = table.scan()
        items = response.get('Items', [])
    
        while 'LastEvaluatedKey' in response:
            response = table.scan(ExclusiveStartKey=response['LastEvaluatedKey'])
            items.extend(response.get('Items', []))
    
        data = items
    except Exception as e:
        print ('Exception: %s' % e)
        statusCode = 500
        raise

    finally:
        return {
            'statusCode': statusCode,
            'body': json.dumps(data),
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'}
        }
