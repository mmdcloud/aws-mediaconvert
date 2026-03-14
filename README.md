# 🚀 AWS MediaConvert Serverless Platform

[![Terraform](https://img.shields.io/badge/Terraform-1.0%2B-623CE4?logo=terraform)](https://www.terraform.io/)
[![AWS](https://img.shields.io/badge/AWS-Serverless-FF9900?logo=amazon-aws)](https://aws.amazon.com/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![MediaConvert](https://img.shields.io/badge/AWS-MediaConvert-orange)](https://aws.amazon.com/mediaconvert/)

A production-ready, fully serverless video transcoding platform built on AWS MediaConvert. This enterprise solution provides automated video processing workflows with S3 event triggers, Lambda functions, API Gateway, CloudFront CDN, and Cognito authentication for secure media transformation at scale.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│                         User Upload Flow                             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │   Next.js Frontend         │
                    │   (S3 + CloudFront)        │
                    └─────────────┬──────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │   API Gateway (REST)       │
                    │   - /get-presigned-url     │
                    │   - /get-records           │
                    │   (Cognito Auth)           │
                    └─────────────┬──────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │   Lambda: Get Presigned    │
                    │   URL for Upload           │
                    └─────────────┬──────────────┘
                                  │
                    ┌─────────────▼──────────────┐
                    │   S3 Source Bucket         │
                    │   (Video Upload)           │
                    └─────────────┬──────────────┘
                                  │ S3 Event Notification
                                  ▼
                    ┌──────────────────────────────┐
                    │   SQS Queue                  │
                    │   (with DLQ)                 │
                    └──────────────┬───────────────┘
                                   │ Event Source Mapping
                                   ▼
                    ┌──────────────────────────────┐
                    │   Lambda: Process Video      │
                    │   - Create MediaConvert Job  │
                    │   - Save to DynamoDB         │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │   AWS MediaConvert           │
                    │   - Transcode Video          │
                    │   - Multiple Outputs         │
                    │   - Adaptive Bitrate         │
                    └──────────────┬───────────────┘
                                   │
                                   ▼
                    ┌──────────────────────────────┐
                    │   S3 Destination Bucket      │
                    │   (Processed Videos)         │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │   CloudFront CDN             │
                    │   (Video Delivery)           │
                    └──────────────────────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │   EventBridge Rule           │
                    │   (Job Status)               │
                    └──────────────┬───────────────┘
                                   │
                    ┌──────────────▼───────────────┐
                    │   SNS Topic                  │
                    │   (Email Notifications)      │
                    └──────────────────────────────┘
```

### Component Architecture

```
Infrastructure Components
├── Frontend
│   ├── S3 Bucket (Next.js Static Site)
│   └── CloudFront Distribution (CDN)
│
├── API Layer
│   ├── API Gateway (REST API)
│   ├── Cognito User Pool (Authentication)
│   └── Lambda Authorizer (Custom Auth)
│
├── Processing Layer
│   ├── Lambda: Get Presigned URL
│   ├── Lambda: Process Video (SQS Trigger)
│   ├── Lambda: Get Records
│   └── Lambda: API Authorizer
│
├── Storage Layer
│   ├── S3 Source Bucket (Uploads)
│   ├── S3 Destination Bucket (Processed)
│   ├── S3 Function Code Buckets (4x)
│   └── DynamoDB Table (Job Records)
│
├── Media Processing
│   ├── AWS MediaConvert (Transcoding)
│   └── CloudFront Distribution (Delivery)
│
├── Event Management
│   ├── SQS Queue + DLQ
│   ├── EventBridge Rule
│   └── SNS Topic
│
└── Networking
    ├── VPC (Multi-AZ)
    ├── Public Subnets (3 AZs)
    ├── Private Subnets (3 AZs)
    └── NAT Gateways (Per AZ)
```

## ✨ Features

### Video Processing
- **Automated Transcoding**: Triggered by S3 uploads
- **Multiple Output Formats**: MP4, HLS, DASH support
- **Adaptive Bitrate Streaming**: Multi-quality outputs
- **Thumbnail Generation**: Automatic video thumbnails
- **Format Conversion**: Support for various input formats
- **Parallel Processing**: SQS-based job queue

### Architecture
- **100% Serverless**: No server management
- **Event-Driven**: S3 → SQS → Lambda → MediaConvert
- **High Availability**: Multi-AZ deployment
- **Auto-Scaling**: Automatic based on demand
- **Cost-Optimized**: Pay only for what you use

### Security
- **Authentication**: Amazon Cognito with email verification
- **API Authorization**: Custom Lambda authorizer
- **Secure Upload**: Pre-signed URLs with time limits
- **CloudFront OAC**: Origin Access Control for S3
- **Encrypted Storage**: S3 server-side encryption
- **Network Isolation**: VPC with private subnets

### Content Delivery
- **CloudFront CDN**: Global edge locations
- **Low Latency**: Edge caching
- **HTTPS Only**: Redirect to secure connections
- **Geo-Restriction**: Configurable geographic limits
- **Cache Control**: Configurable TTL settings

### Monitoring & Notifications
- **Job Status Tracking**: DynamoDB records
- **Email Notifications**: SNS for job completion
- **EventBridge Integration**: Status change events
- **Dead Letter Queue**: Failed job handling
- **CloudWatch Logs**: Comprehensive logging

## 📋 Prerequisites

### Required Software
- **Terraform**: >= 1.0
- **AWS CLI**: >= 2.0, configured with credentials
- **Python**: >= 3.12 (for Lambda functions)
- **Node.js**: >= 18 (for Next.js frontend)
- **zip**: For Lambda deployment packages

### AWS Account Requirements
- Access to AWS MediaConvert service
- IAM permissions for all services
- AWS account with appropriate service quotas

### Lambda Function Code

Prepare the following Lambda function ZIP files in `./files/`:

```bash
files/
├── convert_function.zip       # Main video processing function
├── get_presigned_url.zip      # Presigned URL generation
├── get_records.zip            # DynamoDB query function
└── api_authorizer.zip         # API Gateway authorizer
```

## 🚀 Quick Start

### 1. Prepare Lambda Functions

Create your Lambda function code:

**convert_function.py** (Main processor):
```python
import boto3
import json
import os
from datetime import datetime

mediaconvert = boto3.client('mediaconvert')
dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    # Parse SQS message
    for record in event['Records']:
        body = json.loads(record['body'])
        s3_record = body['Records'][0]
        
        bucket = s3_record['s3']['bucket']['name']
        key = s3_record['s3']['object']['key']
        
        # Create MediaConvert job
        job = create_mediaconvert_job(bucket, key)
        
        # Save to DynamoDB
        save_to_dynamodb(job, key)
        
    return {'statusCode': 200, 'body': 'Success'}

def create_mediaconvert_job(bucket, key):
    # MediaConvert job configuration
    job_settings = {
        "OutputGroups": [{
            "OutputGroupSettings": {
                "Type": "FILE_GROUP_SETTINGS",
                "FileGroupSettings": {
                    "Destination": f"s3://{os.environ['DestinationBucket']}/"
                }
            },
            "Outputs": [{
                "VideoDescription": {
                    "CodecSettings": {
                        "Codec": "H_264",
                        "H264Settings": {
                            "MaxBitrate": 5000000,
                            "RateControlMode": "QVBR"
                        }
                    }
                },
                "AudioDescriptions": [{
                    "CodecSettings": {
                        "Codec": "AAC",
                        "AacSettings": {
                            "Bitrate": 96000,
                            "CodingMode": "CODING_MODE_2_0",
                            "SampleRate": 48000
                        }
                    }
                }],
                "ContainerSettings": {
                    "Container": "MP4"
                }
            }]
        }],
        "Inputs": [{
            "FileInput": f"s3://{bucket}/{key}",
            "AudioSelectors": {
                "Audio Selector 1": {
                    "DefaultSelection": "DEFAULT"
                }
            },
            "VideoSelector": {}
        }]
    }
    
    response = mediaconvert.create_job(
        Role=os.environ['MediaConvertRole'],
        Settings=job_settings
    )
    
    return response['Job']

def save_to_dynamodb(job, filename):
    table = dynamodb.Table(os.environ['TABLE_NAME'])
    table.put_item(
        Item={
            'RecordId': job['Id'],
            'filename': filename,
            'status': job['Status'],
            'created': datetime.now().isoformat()
        }
    )
```

**get_presigned_url.py**:
```python
import boto3
import json
import os

s3 = boto3.client('s3')

def lambda_handler(event, context):
    try:
        # Parse request
        body = json.loads(event.get('body', '{}'))
        filename = body.get('filename')
        
        if not filename:
            return {
                'statusCode': 400,
                'body': json.dumps({'error': 'filename required'})
            }
        
        # Generate presigned URL
        url = s3.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': os.environ['SRC_BUCKET'],
                'Key': filename
            },
            ExpiresIn=3600  # 1 hour
        )
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'uploadUrl': url,
                'filename': filename
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

**get_records.py**:
```python
import boto3
import json
import os
from boto3.dynamodb.conditions import Key

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    try:
        table = dynamodb.Table(os.environ['TABLE_NAME'])
        
        # Scan table (in production, use Query with proper indexes)
        response = table.scan()
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Content-Type': 'application/json'
            },
            'body': json.dumps({
                'records': response.get('Items', []),
                'count': response.get('Count', 0)
            })
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }
```

**api_authorizer.py**:
```python
import boto3
import json
import os

cognito = boto3.client('cognito-idp')

def lambda_handler(event, context):
    try:
        # Extract token from Authorization header
        token = event['authorizationToken'].replace('Bearer ', '')
        
        # Verify token with Cognito
        response = cognito.get_user(AccessToken=token)
        
        # Generate policy
        return generate_policy(response['Username'], 'Allow', event['methodArn'])
    except Exception as e:
        print(f"Authorization failed: {str(e)}")
        return generate_policy('user', 'Deny', event['methodArn'])

def generate_policy(principal_id, effect, resource):
    return {
        'principalId': principal_id,
        'policyDocument': {
            'Version': '2012-10-17',
            'Statement': [{
                'Action': 'execute-api:Invoke',
                'Effect': effect,
                'Resource': resource
            }]
        }
    }
```

### 2. Create ZIP Files

```bash
# Create deployment packages
cd files/
zip convert_function.zip convert_function.py
zip get_presigned_url.zip get_presigned_url.py
zip get_records.zip get_records.py
zip api_authorizer.zip api_authorizer.py
cd ..
```

### 3. Configure Terraform Variables

Create `terraform.tfvars`:

```hcl
# Environment Configuration
env    = "prod"
region = "us-east-1"

# Notification Configuration
notification_email = "your-email@domain.com"

# Network Configuration
azs             = ["us-east-1a", "us-east-1b", "us-east-1c"]
public_subnets  = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
private_subnets = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
```

### 4. Deploy Infrastructure

```bash
# Initialize Terraform
terraform init

# Validate configuration
terraform validate

# Plan deployment
terraform plan

# Deploy infrastructure
terraform apply

# Expected deployment time: 10-15 minutes
```

### 5. Retrieve Outputs

```bash
# Get API endpoint
terraform output api_endpoint

# Get CloudFront URLs
terraform output cloudfront_video_url
terraform output cloudfront_frontend_url

# Get Cognito details
terraform output cognito_user_pool_id
terraform output cognito_client_id

# Get S3 bucket names
terraform output source_bucket
terraform output destination_bucket
```

### 6. Configure Frontend

Update your Next.js application with the outputs:

```javascript
// config.js
export const config = {
  apiEndpoint: 'https://<api-id>.execute-api.us-east-1.amazonaws.com/prod',
  userPoolId: '<user-pool-id>',
  clientId: '<client-id>',
  cdnUrl: 'https://<cloudfront-domain>.cloudfront.net'
};
```

### 7. Test the System

```bash
# 1. Create a Cognito user
aws cognito-idp sign-up \
  --client-id <client-id> \
  --username user@example.com \
  --password TempPassword123! \
  --user-attributes Name=email,Value=user@example.com

# 2. Confirm user (admin)
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id <user-pool-id> \
  --username user@example.com

# 3. Get presigned URL
curl -X POST https://<api-endpoint>/get-presigned-url \
  -H "Content-Type: application/json" \
  -d '{"filename":"test-video.mp4"}'

# 4. Upload video
curl -X PUT "<presigned-url>" \
  --upload-file test-video.mp4

# 5. Check job status
curl https://<api-endpoint>/get-records
```

## 🔧 Configuration

### Input Variables

| Variable | Description | Type | Required | Default |
|----------|-------------|------|----------|---------|
| `env` | Environment name (dev, staging, prod) | `string` | Yes | - |
| `region` | AWS region for deployment | `string` | Yes | `us-east-1` |
| `notification_email` | Email for SNS notifications | `string` | Yes | - |
| `azs` | List of availability zones | `list(string)` | Yes | - |
| `public_subnets` | CIDR blocks for public subnets | `list(string)` | Yes | - |
| `private_subnets` | CIDR blocks for private subnets | `list(string)` | Yes | - |

### DynamoDB Configuration

```hcl
Table Name:        mediaconvert-records-{env}
Partition Key:     RecordId (String)
Sort Key:          filename (String)
Billing Mode:      Provisioned
Read Capacity:     20 units
Write Capacity:    20 units
TTL Enabled:       Yes (TimeToExist)
```

### SQS Configuration

```hcl
Queue Name:                mediaconvert-process-queue-{env}
Visibility Timeout:        180 seconds
Message Retention:         4 days (345600 seconds)
Receive Wait Time:         20 seconds (long polling)
Max Message Size:          256 KB
Dead Letter Queue:         Enabled (maxReceiveCount: 3)
DLQ Retention:             1 day
```

### Lambda Configuration

| Function | Runtime | Memory | Timeout | Trigger |
|----------|---------|--------|---------|---------|
| convert_function | Python 3.12 | 128 MB | 30s | SQS |
| get_presigned_url | Python 3.12 | 128 MB | 30s | API Gateway |
| get_records | Python 3.12 | 128 MB | 30s | API Gateway |
| api_authorizer | Python 3.12 | 128 MB | 10s | API Gateway |

### MediaConvert Settings

Default output settings:
```hcl
Video Codec:       H.264
Video Bitrate:     5 Mbps (QVBR)
Audio Codec:       AAC
Audio Bitrate:     96 Kbps
Sample Rate:       48 kHz
Container:         MP4
```

### CloudFront Configuration

```hcl
Price Class:       PriceClass_200 (US, Europe, Asia)
HTTPS:             Required (redirect)
Caching:           Disabled (TTL: 0)
Compression:       Enabled
Origin Protocol:   S3 with OAC
```

## 🔐 Security Architecture

### Authentication Flow

```
1. User signs up/in via Cognito
2. Cognito returns access token
3. Frontend includes token in API requests
4. API Gateway validates token (optional authorizer)
5. Lambda functions execute with authenticated context
```

### IAM Roles & Policies

**MediaConvert Role**:
- S3 read access to source bucket
- S3 write access to destination bucket

**Lambda Execution Role**:
- CloudWatch Logs (create/write)
- MediaConvert (all operations)
- DynamoDB (read/write to specific table)
- SQS (receive/delete messages)
- Cognito (get user information)
- IAM PassRole (for MediaConvert)

### S3 Bucket Security

**Source Bucket**:
- Versioning enabled
- Event notifications to SQS
- CORS for web uploads
- No public access

**Destination Bucket**:
- Versioning enabled
- CloudFront OAC only access
- No public access
- CORS for CloudFront domain

### Network Security

**VPC Configuration**:
- Public subnets: NAT Gateways, Internet Gateway
- Private subnets: Lambda functions (if VPC-enabled)
- NAT Gateway per AZ for high availability

### Cognito Security

```hcl
Password Policy:
  - Minimum length: 8 characters
  - Require uppercase: Yes
  - Require lowercase: Yes
  - Require numbers: Yes
  - Require symbols: Yes

Email Verification: Required
MFA: Optional (can be enforced)
```

## 📊 Monitoring & Operations

### CloudWatch Metrics

**Lambda Metrics**:
```bash
# Invocation count
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=mediaconvert-lambda-function-prod \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum

# Error rate
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=mediaconvert-lambda-function-prod \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

**SQS Metrics**:
```bash
# Queue depth
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=mediaconvert-process-queue-prod \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Average

# Messages in DLQ
aws cloudwatch get-metric-statistics \
  --namespace AWS/SQS \
  --metric-name ApproximateNumberOfMessagesVisible \
  --dimensions Name=QueueName,Value=mediaconvert-process-dlq-prod \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum
```

**MediaConvert Metrics**:
```bash
# Jobs completed
aws cloudwatch get-metric-statistics \
  --namespace AWS/MediaConvert \
  --metric-name JobsCompletedCount \
  --start-time $(date -u -d '1 day ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Sum
```

### CloudWatch Logs

```bash
# View Lambda logs
aws logs tail /aws/lambda/mediaconvert-lambda-function-prod --follow

# View API Gateway logs (if enabled)
aws logs tail API-Gateway-Execution-Logs_<api-id>/prod --follow

# Search for errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/mediaconvert-lambda-function-prod \
  --filter-pattern "ERROR" \
  --start-time $(date -u -d '1 hour ago' +%s)000
```

### DynamoDB Monitoring

```bash
# Query job records
aws dynamodb scan \
  --table-name mediaconvert-records-prod \
  --max-items 10

# Get specific record
aws dynamodb get-item \
  --table-name mediaconvert-records-prod \
  --key '{"RecordId":{"S":"job-id"},"filename":{"S":"video.mp4"}}'

# Count records
aws dynamodb scan \
  --table-name mediaconvert-records-prod \
  --select COUNT
```

### SNS Notifications

You'll receive email notifications for:
- MediaConvert job started
- MediaConvert job completed
- MediaConvert job failed
- MediaConvert job progressing

### EventBridge Events

Captured events:
```json
{
  "source": ["aws.mediaconvert"],
  "detail-type": ["MediaConvert Job State Change"],
  "detail": {
    "status": ["SUBMITTED", "PROGRESSING", "COMPLETE", "ERROR", "CANCELED"]
  }
}
```

## 💰 Cost Estimation

### Monthly Cost Breakdown (Approximate)

| Service | Usage | Monthly Cost |
|---------|-------|--------------|
| **MediaConvert** | 100 hours HD video | $150-300 |
| **Lambda** | 10,000 invocations/month | $0.20-2 |
| **API Gateway** | 10,000 requests | $0.04 |
| **S3 Storage** | 100 GB source + destination | $4.60 |
| **S3 Requests** | PUT/GET operations | $0.50-2 |
| **CloudFront** | 100 GB data transfer | $8.50 |
| **DynamoDB** | Provisioned capacity | $12.77 |
| **SQS** | 10,000 messages | $0.40 |
| **SNS** | Email notifications | Free tier |
| **Cognito** | < 50,000 MAUs | Free |
| **VPC** | NAT Gateways (3 AZs) | $96-120 |
| **Data Transfer** | Inter-region/Internet | $10-30 |
| **Total** | | **$283-575/month** |

### Cost by Video Processing Volume

| Videos/Month | Total Minutes | Estimated Cost |
|--------------|---------------|----------------|
| 100 videos | 1,000 min | $180-250 |
| 500 videos | 5,000 min | $350-500 |
| 1,000 videos | 10,000 min | $600-900 |
| 5,000 videos | 50,000 min | $2,800-4,200 |

### Cost Optimization Strategies

1. **Use On-Demand Pricing**
   - MediaConvert reserved pricing not required for variable workloads
   - Consider reserved capacity for predictable volumes

2. **Optimize DynamoDB**
   ```hcl
   # Switch to On-Demand billing for variable workloads
   billing_mode = "PAY_PER_REQUEST"
   
   # Or use auto-scaling
   autoscaling_enabled = true
   ```

3. **S3 Lifecycle Policies**
   ```hcl
   # Move old files to cheaper storage
   lifecycle_rule {
     enabled = true
     
     transition {
       days          = 30
       storage_class = "STANDARD_IA"
     }
     
     transition {
       days          = 90
       storage_class = "GLACIER"
     }
     
     expiration {
       days = 365
     }
   }
   ```

4. **CloudFront Optimization**
   - Enable caching (increase TTL)
   - Use signed URLs for private content
   - Consider CloudFront Functions for transformations

5. **Lambda Optimization**
   - Right-size memory allocation
   - Use Lambda Power Tuning tool
   - Minimize cold starts

6. **Reduce NAT Gateway Costs**
   ```hcl
   # Use single NAT gateway for dev/test
   single_nat_gateway = true
   
   # Or use VPC endpoints for AWS services
   ```

## 🐛 Troubleshooting

### Video Upload Failures

**Issue**: Cannot upload video to S3

**Diagnosis**:
```bash
# Check presigned URL generation
aws logs filter-log-events \
  --log-group-name /aws/lambda/mediaconvert-get-presigned-url-function-prod \
  --filter-pattern "ERROR"

# Verify S3 bucket CORS
aws s3api get-bucket-cors --bucket mediaconvert-src-prod
```

**Solutions**:
- Verify CORS configuration allows PUT from your domain
- Check presigned URL expiration time
- Ensure file size is within limits
- Verify Content-Type header matches

### MediaConvert Job Failures

**Issue**: Transcoding jobs fail

**Diagnosis**:
```bash
# List recent jobs
aws mediaconvert list-jobs \
  --max-results 10 \
  --status ERROR

# Get job details
aws mediaconvert get-job \
  --id <job-id>

# Check Lambda logs
aws logs tail /aws/lambda/mediaconvert-lambda-function-prod --follow
```

**Common Solutions**:
- **Invalid Input**: Verify video format is supported
- **Permissions**: Check MediaConvert role has S3 access
- **Codec Issues**: Ensure input codecs are compatible
- **File Corruption**: Re-upload source file
- **Output Path**: Verify destination bucket exists

###SQS Message Processing Issues

**Issue**: Messages stuck in queue or going to DLQ

**Diagnosis**:
```bash
# Check queue attributes
aws sqs get-queue-attributes \
  --queue-url https://sqs.us-east-1.amazonaws.com/<account>/mediaconvert-process-queue-prod \
  --attribute-names All

# View DLQ messages
aws sqs receive-message \
  --queue-url https://sqs.us-east-1.amazonaws.com/<account>/mediaconvert-process-dlq-prod \
  --max-number-of-messages 10

# Check Lambda event source mapping
aws lambda list-event-source-mappings \
  --function-name mediaconvert-lambda-function-prod
```

**Solutions**:
- Increase Lambda timeout if processing takes longer
- Check Lambda error logs for exceptions
- Verify IAM permissions for Lambda to access SQS
- Increase visibility timeout if needed
- Process DLQ messages manually after fixing issues

### API Gateway Errors

**Issue**: 500/502/503 errors from API

**Diagnosis**:
```bash
# Check API Gateway logs (if enabled)
aws logs tail API-Gateway-Execution-Logs_<api-id>/prod --follow

# Test Lambda function directly
aws lambda invoke \
  --function-name mediaconvert-get-presigned-url-function-prod \
  --payload '{"body":"{\"filename\":\"test.mp4\"}"}' \
  response.json

# Check API Gateway configuration
aws apigateway get-rest-api --rest-api-id <api-id>
```

**Solutions**:
- Verify Lambda permissions allow API Gateway invocation
- Check Lambda function logs for errors
- Ensure request/response format matches integration type
- Verify CORS headers in Lambda response
- Check API Gateway resource policy

### Cognito Authentication Issues

**Issue**: Users cannot authenticate

**Diagnosis**:
