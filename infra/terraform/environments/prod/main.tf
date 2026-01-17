# -------------------------------------------------------------------------
# Random Provider Configuration
# -------------------------------------------------------------------------
resource "random_id" "random" {
  byte_length = 8
}


# -------------------------------------------------------------------------
# VPC Configuration
# -------------------------------------------------------------------------
module "vpc" {
  source                  = "../../modules/vpc"
  vpc_name                = "vpc-${var.env}-${var.region}"
  vpc_cidr                = "10.0.0.0/16"
  azs                     = var.azs
  public_subnets          = var.public_subnets
  private_subnets         = var.private_subnets
  enable_dns_hostnames    = true
  enable_dns_support      = true
  create_igw              = true
  map_public_ip_on_launch = true
  enable_nat_gateway      = true
  single_nat_gateway      = true
  one_nat_gateway_per_az  = false
  tags = {
    Project = "mediaconvert"
  }
}

# -------------------------------------------------------------------------
# SNS Configuration
# -------------------------------------------------------------------------
module "mediaconvert_sns" {
  source     = "../../modules/sns"
  topic_name = "mediaconvert-job-status-change-topic-${var.env}"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
}

module "alarm_notification" {
  source     = "../../modules/sns"
  topic_name = "mediaconvert-alarm-notifications-${var.env}"
  subscriptions = [
    {
      protocol = "email"
      endpoint = var.notification_email
    }
  ]
}

# -------------------------------------------------------------------------
# EventBridge Rule
# -------------------------------------------------------------------------
module "mediaconvert_eventbridge_rule" {
  source           = "../../modules/eventbridge"
  rule_name        = "mediaconvert-job-state-change-rule-${var.env}"
  rule_description = "It monitors the media convert job state change event"
  event_pattern = jsonencode({
    source = [
      "aws.mediaconvert"
    ]
    detail-type = [
      "MediaConvert Job State Change"
    ]
  })
  target_id  = "MediaConvertJobStateChange"
  target_arn = module.mediaconvert_sns.topic_arn
}

# -------------------------------------------------------------------------
# DynamoDB Table
# -------------------------------------------------------------------------
module "mediaconvert_dynamodb" {
  source = "../../modules/dynamodb"
  name   = "mediaconvert-records-${var.env}"
  attributes = [
    {
      name = "RecordId"
      type = "S"
    },
    {
      name = "filename"
      type = "S"
    }
  ]
  billing_mode          = "PROVISIONED"
  hash_key              = "RecordId"
  range_key             = "filename"
  read_capacity         = 20
  write_capacity        = 20
  ttl_attribute_name    = "TimeToExist"
  ttl_attribute_enabled = true
}

# -------------------------------------------------------------------------
# SQS configuration
# -------------------------------------------------------------------------
module "mediaconvert_process_sqs" {
  source                     = "../../modules/sqs"
  queue_name                 = "mediaconvert-process-queue-${var.env}"
  delay_seconds              = 0
  maxReceiveCount            = 3
  max_message_size           = 262144
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 180
  receive_wait_time_seconds  = 20
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = "arn:aws:sqs:${var.region}:*:mediaconvert-process-queue-${var.env}"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = module.mediaconvert_source_bucket.arn
          }
        }
      }
    ]
  })
}

module "mediaconvert_process_dlq" {
  source                     = "../../modules/sqs"
  queue_name                 = "mediaconvert-process-dlq-${var.env}"
  delay_seconds              = 0
  maxReceiveCount            = 3
  max_message_size           = 262144
  message_retention_seconds  = 345600
  visibility_timeout_seconds = 180
  receive_wait_time_seconds  = 20
  policy                     = ""
}

# -------------------------------------------------------------------------
# Cognito configuration
# -------------------------------------------------------------------------
module "cognito" {
  source                     = "../../modules/cognito"
  name                       = "mediaconvert-users-${var.env}"
  username_attributes        = ["email"]
  auto_verified_attributes   = ["email"]
  password_minimum_length    = 8
  password_require_lowercase = true
  password_require_numbers   = true
  password_require_symbols   = true
  password_require_uppercase = true
  schema = [
    {
      attribute_data_type = "String"
      name                = "email"
      required            = true
    }
  ]
  verification_message_template_default_email_option = "CONFIRM_WITH_CODE"
  verification_email_subject                         = "Verify your email for MediaConvert"
  verification_email_message                         = "Your verification code is {####}"
  user_pool_clients = [
    {
      name                                 = "mediaconvert_client"
      generate_secret                      = false
      explicit_auth_flows                  = ["ALLOW_USER_PASSWORD_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"]
      allowed_oauth_flows_user_pool_client = true
      allowed_oauth_flows                  = ["code", "implicit"]
      allowed_oauth_scopes                 = ["email", "openid"]
      callback_urls                        = ["https://example.com/callback"]
      logout_urls                          = ["https://example.com/logout"]
      supported_identity_providers         = ["COGNITO"]
    }
  ]
}

#  Lambda SQS event source mapping
resource "aws_lambda_event_source_mapping" "sqs_event_trigger" {
  event_source_arn                   = module.mediaconvert_process_sqs.arn
  function_name                      = module.mediaconvert_lambda_function.arn
  enabled                            = true
  batch_size                         = 10
  maximum_batching_window_in_seconds = 60
}

# -------------------------------------------------------------------------
# S3 Configuration
# -------------------------------------------------------------------------
module "mediaconvert_source_bucket" {
  source             = "../../modules/s3"
  bucket_name        = "mediaconvert-src-${var.env}"
  objects            = []
  versioning_enabled = "Enabled"
  bucket_notification = {
    queue = [
      {
        queue_arn = module.mediaconvert_process_sqs.arn
        events    = ["s3:ObjectCreated:*"]
      }
    ]
    lambda_function = []
  }
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
}

# MediaConvert Destination Bucket
module "mediaconvert_destination_bucket" {
  source             = "../../modules/s3"
  bucket_name        = "mediaconvert-dest-${var.env}"
  objects            = []
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["${module.mediaconvert_cloudfront_distribution.domain_name}"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
  bucket_policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "PolicyForCloudFrontPrivateContent",
    "Statement" : [
      {
        "Sid" : "AllowCloudFrontServicePrincipal",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
        "Action" : "s3:GetObject",
        "Resource" : "${module.mediaconvert_destination_bucket.arn}/*",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : "${module.mediaconvert_cloudfront_distribution.arn}"
          }
        }
      }
    ]
  })
}

# MediaConvert Function Code Bucket
module "mediaconvert_function_code_bucket" {
  source      = "../../modules/s3"
  bucket_name = "mediaconvert-function-code-${var.env}"
  objects = [
    {
      key    = "convert_function.zip"
      source = "../../files/convert_function.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
}

# MediaConvert Get Pre Signed Url Function Code Bucket
module "mediaconvert_get_presigned_url_function_code_bucket" {
  source      = "../../modules/s3"
  bucket_name = "mediaconvert-get-presigned-url-function-code-${var.env}"
  objects = [
    {
      key    = "get_presigned_url.zip"
      source = "../../files/get_presigned_url.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
}

# MediaConvert Get Records Function Code Bucket
module "mediaconvert_get_records_function_code_bucket" {
  source      = "../../modules/s3"
  bucket_name = "mediaconvert-getrecords-code-${var.env}"
  objects = [
    {
      key    = "get_records.zip"
      source = "../../files/get_records.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
}

# MediaConvert API Authorizer Function Code Bucket
module "mediaconvert_api_authorizer_function_code_bucket" {
  source      = "../../modules/s3"
  bucket_name = "mediaconvert-apiauthorizer-code-${var.env}"
  objects = [
    {
      key    = "api_authorizer.zip"
      source = "../../files/api_authorizer.zip"
    }
  ]
  versioning_enabled = "Enabled"
  cors = [
    {
      allowed_headers = ["*"]
      allowed_methods = ["PUT", "POST", "GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
}

# -------------------------------------------------------------------------
# IAM Configuration
# -------------------------------------------------------------------------
module "mediaconvert_iam_role" {
  source             = "../../modules/iam"
  role_name          = "mediaconvert-iam-role-${var.env}"
  role_description   = "MediaConvert IAM Role"
  policy_name        = "mediaconvert-iam-policy-${var.env}"
  policy_description = "MediaConvert IAM Role Policy"
  assume_role_policy = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
              "Service": "mediaconvert.amazonaws.com"
          },
          "Action": "sts:AssumeRole"
        }
      ]
    }
    EOF
  policy             = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
        "Effect": "Allow",
        "Action": [
                "s3:*"
            ],
            "Resource": [
              "${module.mediaconvert_source_bucket.arn}/*",
              "${module.mediaconvert_destination_bucket.arn}/*"
            ]
        }
      ]
    }
    EOF
}

# Lambda function IAM Role
module "mediaconvert_function_iam_role" {
  source             = "../../modules/iam"
  role_name          = "mediaconvert-function-iam-role-${var.env}"
  role_description   = "MediaConvert Function IAM Role"
  policy_name        = "mediaconvert-function-iam-policy-${var.env}"
  policy_description = "MediaConvert Function IAM Role Policy"
  assume_role_policy = <<EOF
    {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Action": "sts:AssumeRole",
                "Principal": {
                  "Service": "lambda.amazonaws.com"
                },
                "Effect": "Allow",
                "Sid": ""
            }
        ]
    }
    EOF
  policy             = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Action": [
                "logs:CreateLogGroup",
                "logs:CreateLogStream",
                "logs:PutLogEvents",
                "mediaconvert:*"
              ],
              "Resource": "arn:aws:logs:*:*:*",
              "Effect": "Allow"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "mediaconvert:*",
                  "s3:ListAllMyBuckets",
                  "s3:ListBucket"
              ],
              "Resource": "*"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "dynamodb:*"
              ],
	            "Resource": "${module.mediaconvert_dynamodb.arn}"
          },
          {
              "Effect": "Allow",
              "Action": [
                  "iam:PassRole"
              ],
              "Resource": "*",
              "Condition": {
                  "StringLike": {
                      "iam:PassedToService": [
                          "mediaconvert.amazonaws.com"
                      ]
                  }
              }
          },
          {
              "Action": [
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage",
                "sqs:GetQueueAttributes"
              ],
              "Effect"   : "Allow",
              "Resource" : "${module.mediaconvert_process_sqs.arn}"
          },
          {
            "Action": [
                "cognito-idp:GetUser",
                "cognito-idp:ListUsers"
              ],
              "Effect"   : "Allow",
              "Resource" : "${module.cognito.user_pool_arn}"
          },
          {
            "Action": [
              "sqs:*"
            ],
            "Effect"   : "Allow",
            "Resource" : "${module.mediaconvert_process_dlq.arn}"
          },
          {
            "Action": [
              "ec2:CreateNetworkInterface",
              "ec2:DescribeNetworkInterfaces",
              "ec2:DeleteNetworkInterface"
            ],
            "Effect"   : "Allow",
            "Resource" : "*"
          }
      ]
    }
    EOF
}

# -------------------------------------------------------------------------
# Lambda Configuration
# -------------------------------------------------------------------------
module "mediaconvert_lambda_function" {
  source        = "../../modules/lambda"
  function_name = "mediaconvert-lambda-function-${var.env}"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    REGION            = var.region
    DestinationBucket = "${module.mediaconvert_destination_bucket.bucket}"
    MediaConvertRole  = "${module.mediaconvert_iam_role.arn}"
    TABLE_NAME        = "${module.mediaconvert_dynamodb.name}"
  }
  dead_letter_config = {
    target_arn = module.mediaconvert_process_dlq.arn
  }
  handler    = "convert_function.lambda_handler"
  runtime    = "python3.12"
  s3_bucket  = module.mediaconvert_function_code_bucket.bucket
  s3_key     = "convert_function.zip"
  depends_on = [module.mediaconvert_function_code_bucket]
}

# Lambda function to get presigned url
module "mediaconvert_get_presigned_url_function" {
  source        = "../../modules/lambda"
  function_name = "mediaconvert-get-presigned-url-function-${var.env}"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    REGION     = var.region
    SRC_BUCKET = "${module.mediaconvert_source_bucket.bucket}"
  }
  permissions = [
    {
      statement_id = "InvokeGetPresignedUrl"
      action       = "lambda:InvokeFunction"
      principal    = "apigateway.amazonaws.com"
      source_arn   = "${aws_api_gateway_rest_api.mediaconvert_rest_api.execution_arn}/*/*/get-presigned-url"
    }
  ]
  handler    = "get_presigned_url.lambda_handler"
  runtime    = "python3.12"
  s3_bucket  = module.mediaconvert_get_presigned_url_function_code_bucket.bucket
  s3_key     = "get_presigned_url.zip"
  depends_on = [module.mediaconvert_get_presigned_url_function_code_bucket]
}

# Lambda function to get processed records from DynamoDB
module "mediaconvert_get_records_function" {
  source        = "../../modules/lambda"
  function_name = "mediaconvert-get-records-function-${var.env}"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    REGION     = var.region
    TABLE_NAME = "${module.mediaconvert_dynamodb.name}"
  }
  permissions = [
    {
      statement_id = "InvokeGetRecords"
      action       = "lambda:InvokeFunction"
      principal    = "apigateway.amazonaws.com"
      source_arn   = "${aws_api_gateway_rest_api.mediaconvert_rest_api.execution_arn}/*/*/get-records"
    }
  ]
  handler    = "get_records.lambda_handler"
  runtime    = "python3.12"
  s3_bucket  = module.mediaconvert_get_records_function_code_bucket.bucket
  s3_key     = "get_records.zip"
  depends_on = [module.mediaconvert_get_records_function_code_bucket]
}

# Lambda authorizer function for API Gateway
module "mediaconvert_api_authorizer_function" {
  source        = "../../modules/lambda"
  function_name = "mediaconvert-api-authorizer-function-${var.env}"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    USER_POOL_ID  = module.cognito.user_pool_id
    APP_CLIENT_ID = module.cognito.client_ids[0]
    REGION        = var.region
  }
  permissions = [
    {
      statement_id = "AllowAPIGatewayInvoke"
      action       = "lambda:InvokeFunction"
      principal    = "apigateway.amazonaws.com"
      source_arn   = "${aws_api_gateway_rest_api.mediaconvert_rest_api.execution_arn}/*/*/*"
    }
  ]
  handler    = "api_authorizer.lambda_handler"
  runtime    = "python3.12"
  s3_bucket  = module.mediaconvert_api_authorizer_function_code_bucket.bucket
  s3_key     = "api_authorizer.zip"
  depends_on = [module.mediaconvert_api_authorizer_function_code_bucket]
}

# -------------------------------------------------------------------------
# Cloudfront distribution
# -------------------------------------------------------------------------
module "mediaconvert_cloudfront_distribution" {
  source                                = "../../modules/cloudfront"
  distribution_name                     = "mediaconvert_cdn-${var.env}"
  oac_name                              = "mediaconvert_cdn_oac-${var.env}"
  oac_description                       = "mediaconvert_cdn_oac-${var.env}"
  oac_origin_access_control_origin_type = "s3"
  oac_signing_behavior                  = "always"
  oac_signing_protocol                  = "sigv4"
  enabled                               = true
  origin = [
    {
      origin_id           = "mediaconvertdestmadmax-${var.env}"
      domain_name         = "mediaconvertdestmadmax-${var.env}.s3.${var.region}.amazonaws.com"
      connection_attempts = 3
      connection_timeout  = 10
    }
  ]
  compress                       = true
  smooth_streaming               = false
  target_origin_id               = "mediaconvertdestmadmax-${var.env}"
  allowed_methods                = ["GET", "HEAD"]
  cached_methods                 = ["GET", "HEAD"]
  viewer_protocol_policy         = "redirect-to-https"
  min_ttl                        = 0
  default_ttl                    = 0
  max_ttl                        = 0
  price_class                    = "PriceClass_200"
  forward_cookies                = "all"
  cloudfront_default_certificate = true
  geo_restriction_type           = "none"
  query_string                   = true
}

# Next.js application bucket
module "mediaconvert_frontend_bucket" {
  source             = "../../modules/s3"
  bucket_name        = "mediaconvert-frontend-${var.env}"
  objects            = []
  versioning_enabled = "Enabled"
  bucket_notification = {
    queue           = []
    lambda_function = []
  }
  cors = [
    {
      allowed_headers = ["${module.mediaconvert_frontend_cloudfront_distribution.domain_name}"]
      allowed_methods = ["GET"]
      allowed_origins = ["*"]
      max_age_seconds = 3000
    }
  ]
  force_destroy = true
  bucket_policy = jsonencode({
    "Version" : "2012-10-17",
    "Id" : "PolicyForCloudFrontPrivateContent",
    "Statement" : [
      {
        "Sid" : "AllowCloudFrontServicePrincipal",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "cloudfront.amazonaws.com"
        },
        "Action" : "s3:GetObject",
        "Resource" : "${module.mediaconvert_frontend_bucket.arn}/*",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : "${module.mediaconvert_frontend_cloudfront_distribution.arn}"
          }
        }
      }
    ]
  })
}

# MediaConvert Cloudfront distribution
module "mediaconvert_frontend_cloudfront_distribution" {
  source                                = "../../modules/cloudfront"
  distribution_name                     = "mediaconvert_cdn_frontend-${var.env}"
  oac_name                              = "mediaconvert_cdn_frontend_oac-${var.env}"
  oac_description                       = "mediaconvert_cdn_frontend_oac-${var.env}"
  oac_origin_access_control_origin_type = "s3"
  oac_signing_behavior                  = "always"
  oac_signing_protocol                  = "sigv4"
  enabled                               = true
  origin = [
    {
      origin_id           = "mediaconvertfrontendorigin-${var.env}"
      domain_name         = "mediaconvertfrontendorigin-${var.env}.s3.${var.region}.amazonaws.com"
      connection_attempts = 3
      connection_timeout  = 10
    }
  ]
  compress                       = true
  smooth_streaming               = false
  target_origin_id               = "mediaconvertfrontendorigin-${var.env}"
  allowed_methods                = ["GET", "HEAD"]
  cached_methods                 = ["GET", "HEAD"]
  viewer_protocol_policy         = "redirect-to-https"
  min_ttl                        = 0
  default_ttl                    = 0
  max_ttl                        = 0
  price_class                    = "PriceClass_200"
  forward_cookies                = "all"
  cloudfront_default_certificate = true
  geo_restriction_type           = "none"
  query_string                   = true
}

# -------------------------------------------------------------------------
# API Gateway configuration
# -------------------------------------------------------------------------
resource "aws_api_gateway_rest_api" "mediaconvert_rest_api" {
  name = "mediaconvert-api-${var.env}"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

# Authorizer Resource
# resource "aws_api_gateway_authorizer" "cognito_authorizer" {
#   name            = "mediaconvert-cognito-authorizer"
#   rest_api_id     = aws_api_gateway_rest_api.mediaconvert_rest_api.id
#   authorizer_uri  = module.mediaconvert_api_authorizer_function.invoke_arn
#   identity_source = "method.request.header.Authorization"
#   type            = "REQUEST"
# }

resource "aws_api_gateway_resource" "mediaconvert_resource_api" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  parent_id   = aws_api_gateway_rest_api.mediaconvert_rest_api.root_resource_id
  path_part   = "get-presigned-url"
}

resource "aws_api_gateway_method" "mediaconvert_resource_api_get_presigned_url_method" {
  rest_api_id      = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id      = aws_api_gateway_resource.mediaconvert_resource_api.id
  api_key_required = false
  http_method      = "ANY"
  authorization    = "NONE"
  # authorizer_id    = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "mediaconvert_resource_api_get_presigned_url_method_integration" {
  rest_api_id             = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id             = aws_api_gateway_resource.mediaconvert_resource_api.id
  http_method             = aws_api_gateway_method.mediaconvert_resource_api_get_presigned_url_method.http_method
  integration_http_method = "ANY"
  type                    = "AWS_PROXY"
  uri                     = module.mediaconvert_get_presigned_url_function.invoke_arn
}

resource "aws_api_gateway_method_response" "get_presigned_url_method_response_200" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id = aws_api_gateway_resource.mediaconvert_resource_api.id
  http_method = aws_api_gateway_method.mediaconvert_resource_api_get_presigned_url_method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "get_presigned_url_integration_response_200" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id = aws_api_gateway_resource.mediaconvert_resource_api.id
  http_method = aws_api_gateway_method.mediaconvert_resource_api_get_presigned_url_method.http_method
  status_code = aws_api_gateway_method_response.get_presigned_url_method_response_200.status_code
  depends_on = [
    aws_api_gateway_integration.mediaconvert_resource_api_get_presigned_url_method_integration
  ]
}

# ---------------------------------------------------------------------------------------------------

resource "aws_api_gateway_resource" "mediaconvert_get_records_api" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  parent_id   = aws_api_gateway_rest_api.mediaconvert_rest_api.root_resource_id
  path_part   = "get-records"
}

resource "aws_api_gateway_method" "mediaconvert_resource_api_get_records_method" {
  rest_api_id      = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id      = aws_api_gateway_resource.mediaconvert_get_records_api.id
  api_key_required = false
  http_method      = "ANY"
  authorization    = "NONE"
  # authorizer_id    = aws_api_gateway_authorizer.cognito_authorizer.id
}

resource "aws_api_gateway_integration" "mediaconvert_resource_api_get_records_method_integration" {
  rest_api_id             = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id             = aws_api_gateway_resource.mediaconvert_get_records_api.id
  http_method             = aws_api_gateway_method.mediaconvert_resource_api_get_records_method.http_method
  integration_http_method = "ANY"
  type                    = "AWS_PROXY"
  uri                     = module.mediaconvert_get_records_function.invoke_arn
}

resource "aws_api_gateway_method_response" "get_records_method_response_200" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id = aws_api_gateway_resource.mediaconvert_get_records_api.id
  http_method = aws_api_gateway_method.mediaconvert_resource_api_get_records_method.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "get_records_integration_response_200" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  resource_id = aws_api_gateway_resource.mediaconvert_get_records_api.id
  http_method = aws_api_gateway_method.mediaconvert_resource_api_get_records_method.http_method
  status_code = aws_api_gateway_method_response.get_records_method_response_200.status_code
  depends_on = [
    aws_api_gateway_integration.mediaconvert_resource_api_get_records_method_integration
  ]
}

resource "aws_api_gateway_deployment" "mediaconvert_api_deployment" {
  rest_api_id = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  lifecycle {
    create_before_destroy = true
  }
  depends_on = [aws_api_gateway_integration.mediaconvert_resource_api_get_presigned_url_method_integration, aws_api_gateway_integration.mediaconvert_resource_api_get_records_method_integration]
}

resource "aws_api_gateway_stage" "mediaconvert_api_stage" {
  deployment_id = aws_api_gateway_deployment.mediaconvert_api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.mediaconvert_rest_api.id
  stage_name    = var.env
}

# -------------------------------------------------------------------------
# Monitoring & Alerting Configuration
# -------------------------------------------------------------------------
module "convert_function_errors" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-lambda-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when convert function has more than 5 errors in 10 minutes"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.mediaconvert_lambda_function.function_name
  }

  tags = {
    Severity = "Critical"
    Service  = "Lambda"
  }
}

module "convert_function_throttles" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-lambda-throttles-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "3"
  alarm_description   = "Alert when convert function is throttled"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.mediaconvert_lambda_function.function_name
  }

  tags = {
    Severity = "Warning"
    Service  = "Lambda"
  }
}

module "convert_function_duration" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-lambda-duration-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Average"
  threshold           = "150000" # 150 seconds (adjust based on your timeout)
  alarm_description   = "Alert when convert function duration is high"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.mediaconvert_lambda_function.function_name
  }

  tags = {
    Severity = "Warning"
    Service  = "Lambda"
  }
}

module "convert_function_concurrent_executions" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-lambda-concurrent-executions-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ConcurrentExecutions"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "80" # 80% of your account limit
  alarm_description   = "Alert when concurrent executions are high"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.mediaconvert_lambda_function.function_name
  }

  tags = {
    Severity = "Warning"
    Service  = "Lambda"
  }
}

module "get_presigned_url_function_errors" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-get-presigned-url-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when get presigned URL function has errors"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.mediaconvert_get_presigned_url_function.function_name
  }

  tags = {
    Severity = "Warning"
    Service  = "Lambda"
  }
}

module "get_records_function_errors" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-get-records-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when get records function has errors"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.mediaconvert_get_records_function.function_name
  }

  tags = {
    Severity = "Warning"
    Service  = "Lambda"
  }
}

module "api_gateway_4xx_errors" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-api-4xx-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "50"
  alarm_description   = "Alert when API Gateway has high 4XX errors"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.mediaconvert_rest_api.name
    Stage   = aws_api_gateway_stage.mediaconvert_api_stage.stage_name
  }

  tags = {
    Severity = "Warning"
    Service  = "API Gateway"
  }
}

module "api_gateway_5xx_errors" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-api-5xx-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "5XXError"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "Alert when API Gateway has 5XX errors (critical)"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.mediaconvert_rest_api.name
    Stage   = aws_api_gateway_stage.mediaconvert_api_stage.stage_name
  }

  tags = {
    Severity = "Critical"
    Service  = "API Gateway"
  }
}

module "api_gateway_latency" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-api-latency-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Latency"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000" # 5 seconds
  alarm_description   = "Alert when API Gateway latency is high"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    ApiName = aws_api_gateway_rest_api.mediaconvert_rest_api.name
    Stage   = aws_api_gateway_stage.mediaconvert_api_stage.stage_name
  }

  tags = {
    Severity = "Warning"
    Service  = "API Gateway"
  }
}

module "sqs_dlq_messages" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-dlq-messages-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "1"
  alarm_description   = "Alert when messages appear in DLQ"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.mediaconvert_process_dlq.queue_name
  }

  tags = {
    Severity = "Critical"
    Service  = "SQS"
  }
}

module "sqs_oldest_message_age" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-sqs-old-messages-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateAgeOfOldestMessage"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Maximum"
  threshold           = "1800" # 30 minutes
  alarm_description   = "Alert when messages are stuck in queue for too long"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.mediaconvert_process_sqs.queue_name
  }

  tags = {
    Severity = "Warning"
    Service  = "SQS"
  }
}

module "sqs_queue_depth" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-sqs-queue-depth-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = "300"
  statistic           = "Average"
  threshold           = "100"
  alarm_description   = "Alert when queue has too many messages"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = module.mediaconvert_process_sqs.queue_name
  }

  tags = {
    Severity = "Warning"
    Service  = "SQS"
  }
}

module "dynamodb_read_throttles" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-dynamodb-read-throttles-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ReadThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when DynamoDB reads are throttled"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = module.mediaconvert_dynamodb.name
  }

  tags = {
    Severity = "Warning"
    Service  = "DynamoDB"
  }
}

module "dynamodb_write_throttles" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-dynamodb-write-throttles-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "WriteThrottleEvents"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when DynamoDB writes are throttled"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = module.mediaconvert_dynamodb.name
  }

  tags = {
    Severity = "Critical"
    Service  = "DynamoDB"
  }
}

module "dynamodb_system_errors" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-dynamodb-system-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "SystemErrors"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Alert when DynamoDB has system errors"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = module.mediaconvert_dynamodb.name
  }

  tags = {
    Severity = "Critical"
    Service  = "DynamoDB"
  }
}

module "dynamodb_consumed_read_capacity" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-dynamodb-high-read-capacity-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConsumedReadCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "16" # 80% of provisioned 20 units
  alarm_description   = "Alert when DynamoDB read capacity is high"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = module.mediaconvert_dynamodb.name
  }

  tags = {
    Severity = "Warning"
    Service  = "DynamoDB"
  }
}

module "dynamodb_consumed_write_capacity" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-dynamodb-high-write-capacity-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ConsumedWriteCapacityUnits"
  namespace           = "AWS/DynamoDB"
  period              = "300"
  statistic           = "Average"
  threshold           = "16" # 80% of provisioned 20 units
  alarm_description   = "Alert when DynamoDB write capacity is high"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    TableName = module.mediaconvert_dynamodb.name
  }

  tags = {
    Severity = "Warning"
    Service  = "DynamoDB"
  }
}

module "cloudfront_5xx_error_rate" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-cloudfront-5xx-errors-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = "5" # 5% error rate
  alarm_description   = "Alert when CloudFront has high 5XX error rate"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = module.mediaconvert_cloudfront_distribution.distribution_id
  }

  tags = {
    Severity = "Critical"
    Service  = "CloudFront"
  }
}

module "cloudfront_origin_latency" {
  source              = "../../modules/cloudwatch/cloudwatch-alarm"
  alarm_name          = "mediaconvert-cloudfront-origin-latency-${var.env}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "OriginLatency"
  namespace           = "AWS/CloudFront"
  period              = "300"
  statistic           = "Average"
  threshold           = "5000" # 5 seconds
  alarm_description   = "Alert when CloudFront origin latency is high"
  alarm_actions       = [module.alarm_notification.topic_arn]
  ok_actions          = [module.alarm_notification.topic_arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    DistributionId = module.mediaconvert_cloudfront_distribution.distribution_id
  }

  tags = {
    Severity = "Warning"
    Service  = "CloudFront"
  }
}

# module "mediaconvert_job_failures" {
#   source              = "../../modules/cloudwatch/cloudwatch-alarm"
#   alarm_name          = "mediaconvert-job-failures-${var.env}"
#   comparison_operator = "GreaterThanThreshold"
#   evaluation_periods  = "1"
#   metric_name         = "JobFailures"
#   namespace           = "MediaConvert"
#   period              = "300"
#   statistic           = "Sum"
#   threshold           = "3"
#   alarm_description   = "Alert when MediaConvert jobs fail"
#   alarm_actions       = [module.alarm_notification.topic_arn]
#   ok_actions          = [module.alarm_notification.topic_arn]
#   treat_missing_data  = "notBreaching"

#   tags = {
#     Severity = "Critical"
#     Service  = "MediaConvert"
#   }
# }