import glob
import json
import os
import uuid
import boto3
import datetime
import random

from botocore.client import ClientError

def lambda_handler(event, context):
    dynamodb = boto3.client('dynamodb')
    table_name = os.getenv('TABLE_NAME')
    assetID = str(uuid.uuid4())
    rec = json.loads(event['Records'][0]['body'])
    sourceS3Bucket = rec['Records'][0]['s3']['bucket']['name']
    sourceS3Key = rec['Records'][0]['s3']['object']['key']
    sourceS3 = 's3://'+ sourceS3Bucket + '/' + sourceS3Key
    sourceS3Basename = os.path.splitext(os.path.basename(sourceS3))[0]
    destinationS3 = 's3://' + os.environ['DestinationBucket']
    destinationS3basename = os.path.splitext(os.path.basename(destinationS3))[0]
    mediaConvertRole = os.environ['MediaConvertRole']
    region = os.getenv('REGION')
    statusCode = 200
    body = {}
    
    # Use MediaConvert SDK UserMetadata to tag jobs with the assetID 
    # Events from MediaConvert will have the assetID in UserMedata
    jobMetadata = {'assetID': assetID}

    print (json.dumps(event))
    
    try:
        # Job settings are in the lambda zip file in the current working directory
        with open('job.json') as json_data:
            jobSettings = json.load(json_data)
            print(jobSettings)
        
        # get the account-specific mediaconvert endpoint for this region
        mc_client = boto3.client('mediaconvert', region_name=region)
        endpoints = mc_client.describe_endpoints()

        # add the account-specific endpoint to the client session 
        client = boto3.client('mediaconvert', region_name=region, endpoint_url=endpoints['Endpoints'][0]['Url'], verify=False)

        # Update the job settings with the source video from the S3 event and destination 
        # paths for converted videos
        jobSettings['Inputs'][0]['FileInput'] = sourceS3
        
        S3KeyHLS = sourceS3Key + '/assets/' + assetID + '/HLS/' + sourceS3Basename
        jobSettings['OutputGroups'][0]['OutputGroupSettings']['HlsGroupSettings']['Destination'] \
            = destinationS3 + '/' + S3KeyHLS
         
        S3KeyWatermark = sourceS3Key + '/assets/' + assetID + '/MP4/' + sourceS3Basename
        jobSettings['OutputGroups'][1]['OutputGroupSettings']['FileGroupSettings']['Destination'] \
            = destinationS3 + '/' + S3KeyWatermark
        
        S3KeyThumbnails = sourceS3Key + '/assets/' + assetID + '/Thumbnails/' + sourceS3Basename
        jobSettings['OutputGroups'][2]['OutputGroupSettings']['FileGroupSettings']['Destination'] \
            = destinationS3 + '/' + S3KeyThumbnails     

        print('jobSettings:')
        print(json.dumps(jobSettings))

        # Convert the video using AWS Elemental MediaConvert
        job = client.create_job(Role=mediaConvertRole, UserMetadata=jobMetadata, Settings=jobSettings)
        print (json.dumps(job, default=str))
        
        # Storing asset information in DynamoDB
        dynamodb.put_item(TableName=table_name, Item={'RecordId':{"S":assetID},'filename':{"S":sourceS3Key}})
    except Exception as e:
        print ('Exception: %s' % e)
        statusCode = 500
        raise

    finally:
        return {
            'statusCode': statusCode,
            'body': json.dumps(body),
            'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'}
        }