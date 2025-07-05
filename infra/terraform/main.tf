resource "random_id" "random" {
  byte_length = 8
}

# MediaConvert SNS Configuration
module "mediaconvert_sns" {
  source     = "./modules/sns"
  topic_name = "mediaconvert-job-status-change-topic"
  subscriptions = [
    {
      protocol = "email"
      endpoint = "madmaxcloudonline@gmail.com"
    }
  ]
}

# MediaConvert EventBridge Rule
module "mediaconvert_eventbridge_rule" {
  source           = "./modules/eventbridge"
  rule_name        = "mediaconvert-job-state-change-rule"
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

# DynamoDB Table
module "mediaconvert_dynamodb" {
  source = "./modules/dynamodb"
  name   = "mediaconvert-records"
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

# MediaConvert SQS
module "mediaconvert_sqs" {
  source                        = "./modules/sqs"
  queue_name                    = "mediaconvert-process-queue"
  delay_seconds                 = 0
  maxReceiveCount               = 3
  dlq_message_retention_seconds = 86400
  dlq_name                      = "mediaconvert-process-dlq"
  max_message_size              = 262144
  message_retention_seconds     = 345600
  visibility_timeout_seconds    = 180
  receive_wait_time_seconds     = 20
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "s3.amazonaws.com" }
        Action    = "sqs:SendMessage"
        Resource  = "arn:aws:sqs:${var.region}:*:mediaconvert-process-queue"
        Condition = {
          ArnEquals = {
            "aws:SourceArn" = module.mediaconvert_source_bucket.arn
          }
        }
      }
    ]
  })
}

module "cognito" {
  source                     = "./modules/cognito"
  name                       = "mediaconvert-users"
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
  event_source_arn                   = module.mediaconvert_sqs.arn
  function_name                      = module.mediaconvert_lambda_function.arn
  enabled                            = true
  batch_size                         = 10
  maximum_batching_window_in_seconds = 60
}

# MediaConvert Source Bucket
module "mediaconvert_source_bucket" {
  source             = "./modules/s3"
  bucket_name        = "mediaconvert-src-${random_id.random.hex}"
  objects            = []
  versioning_enabled = "Enabled"
  bucket_notification = {
    queue = [
      {
        queue_arn = module.mediaconvert_sqs.arn
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
  source             = "./modules/s3"
  bucket_name        = "mediaconvert-dest-${random_id.random.hex}"
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
  source      = "./modules/s3"
  bucket_name = "mediaconvert-function-code-${random_id.random.hex}"
  objects = [
    {
      key    = "convert_function.zip"
      source = "./files/convert_function.zip"
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
  source      = "./modules/s3"
  bucket_name = "mediaconvert-get-presigned-url-function-code-${random_id.random.hex}"
  objects = [
    {
      key    = "get_presigned_url.zip"
      source = "./files/get_presigned_url.zip"
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
  source      = "./modules/s3"
  bucket_name = "mediaconvert-getrecords-code-${random_id.random.hex}"
  objects = [
    {
      key    = "get_records.zip"
      source = "./files/get_records.zip"
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
  source      = "./modules/s3"
  bucket_name = "mediaconvert-apiauthorizer-code-${random_id.random.hex}"
  objects = [
    {
      key    = "api_authorizer.zip"
      source = "./files/api_authorizer.zip"
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

# MediaConvert IAM Role
module "mediaconvert_iam_role" {
  source             = "./modules/iam"
  role_name          = "mediaconvert-iam-role"
  role_description   = "mediaconvert-iam-role"
  policy_name        = "mediaconvert-iam-policy"
  policy_description = "mediaconvert-iam-policy"
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
  source             = "./modules/iam"
  role_name          = "mediaconvert-function-iam-role"
  role_description   = "mediaconvert-function-iam-role"
  policy_name        = "mediaconvert-function-iam-policy"
  policy_description = "mediaconvert-function-iam-policy"
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
              "Resource" : "${module.mediaconvert_sqs.arn}"
          },
          {
            "Action": [
                "cognito-idp:GetUser",
                "cognito-idp:ListUsers"
              ],
              "Effect"   : "Allow",
              "Resource" : "${module.cognito.user_pool_arn}"
          }
      ]
    }
    EOF
}

# Lambda function to process media files
module "mediaconvert_lambda_function" {
  source        = "./modules/lambda"
  function_name = "mediaconvert-lambda-function"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    REGION            = var.region
    DestinationBucket = "${module.mediaconvert_destination_bucket.bucket}"
    MediaConvertRole  = "${module.mediaconvert_iam_role.arn}"
    TABLE_NAME = "${module.mediaconvert_dynamodb.name}"
  }
  handler    = "convert_function.lambda_handler"
  runtime    = "python3.12"
  s3_bucket  = module.mediaconvert_function_code_bucket.bucket
  s3_key     = "convert_function.zip"
  depends_on = [module.mediaconvert_function_code_bucket]
}

# Lambda function to get presigned url
module "mediaconvert_get_presigned_url_function" {
  source        = "./modules/lambda"
  function_name = "mediaconvert-get-presigned-url-function"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    REGION = var.region
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
  source        = "./modules/lambda"
  function_name = "mediaconvert-get-records-function"
  role_arn      = module.mediaconvert_function_iam_role.arn
  env_variables = {
    REGION = var.region
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
  source        = "./modules/lambda"
  function_name = "mediaconvert-api-authorizer-function"
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

# MediaConvert Cloudfront distribution
module "mediaconvert_cloudfront_distribution" {
  source                                = "./modules/cloudfront"
  distribution_name                     = "mediaconvert_cdn"
  oac_name                              = "mediaconvert_cdn_oac"
  oac_description                       = "mediaconvert_cdn_oac"
  oac_origin_access_control_origin_type = "s3"
  oac_signing_behavior                  = "always"
  oac_signing_protocol                  = "sigv4"
  enabled                               = true
  origin = [
    {
      origin_id           = "mediaconvertdestmadmax"
      domain_name         = "mediaconvertdestmadmax.s3.${var.region}.amazonaws.com"
      connection_attempts = 3
      connection_timeout  = 10
    }
  ]
  compress                       = true
  smooth_streaming               = false
  target_origin_id               = "mediaconvertdestmadmax"
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

# Frontend Module
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC Configuration
module "vpc" {
  source                = "./modules/vpc/vpc"
  vpc_name              = "mediaconvert-vpc"
  vpc_cidr_block        = "10.0.0.0/16"
  enable_dns_hostnames  = true
  enable_dns_support    = true
  internet_gateway_name = "vpc_igw"
}

# Security Group
module "security_group" {
  source = "./modules/vpc/security_groups"
  vpc_id = module.vpc.vpc_id
  name   = "mediaconvert-security-group"
  ingress = [
    {
      from_port       = 80
      to_port         = 80
      protocol        = "tcp"
      self            = "false"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
      description     = "any"
    },
    {
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      self            = "false"
      cidr_blocks     = ["0.0.0.0/0"]
      security_groups = []
      description     = "any"
    }
  ]
  egress = [
    {
      from_port   = 0
      to_port     = 0
      protocol    = "-1"
      cidr_blocks = ["0.0.0.0/0"]
    }
  ]
}

# Public Subnets
module "public_subnets" {
  source = "./modules/vpc/subnets"
  name   = "mediaconvert-public-subnet"
  subnets = [
    {
      subnet = "10.0.1.0/24"
      az     = "us-east-1a"
    },
    {
      subnet = "10.0.2.0/24"
      az     = "us-east-1b"
    },
    {
      subnet = "10.0.3.0/24"
      az     = "us-east-1c"
    }
  ]
  vpc_id                  = module.vpc.vpc_id
  map_public_ip_on_launch = true
}

# Private Subnets
module "private_subnets" {
  source = "./modules/vpc/subnets"
  name   = "mediaconvert-private-subnet"
  subnets = [
    {
      subnet = "10.0.6.0/24"
      az     = "us-east-1a"
    },
    {
      subnet = "10.0.5.0/24"
      az     = "us-east-1b"
    },
    {
      subnet = "10.0.4.0/24"
      az     = "us-east-1c"
    }
  ]
  vpc_id                  = module.vpc.vpc_id
  map_public_ip_on_launch = false
}

# Public Route Table
module "public_rt" {
  source  = "./modules/vpc/route_tables"
  name    = "mediaconvert-public-route-table"
  subnets = module.public_subnets.subnets[*]
  routes = [
    {
      cidr_block = "0.0.0.0/0"
      gateway_id = module.vpc.igw_id
    }
  ]
  vpc_id = module.vpc.vpc_id
}

# Private Route Table
module "private_rt" {
  source  = "./modules/vpc/route_tables"
  name    = "mediaconvert-private-route-table"
  subnets = module.private_subnets.subnets[*]
  routes  = []
  vpc_id  = module.vpc.vpc_id
}

# EC2 IAM Instance Profile
data "aws_iam_policy_document" "instance_profile_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "instance_profile_iam_role" {
  name               = "mediaconvert-instance-profile-role"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.instance_profile_assume_role.json
}

data "aws_iam_policy_document" "instance_profile_policy_document" {
  statement {
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = ["${module.mediaconvert_source_bucket.arn}/*"]
  }
  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:*"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "instance_profile_s3_policy" {
  role   = aws_iam_role.instance_profile_iam_role.name
  policy = data.aws_iam_policy_document.instance_profile_policy_document.json
}

resource "aws_iam_instance_profile" "iam_instance_profile" {
  name = "mediaconvert-iam-instance-profile"
  role = aws_iam_role.instance_profile_iam_role.name
}

module "mediaconvert_frontend_instance" {
  source                      = "./modules/ec2"
  name                        = "mediaconvert-frontend-instance"
  ami_id                      = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = "madmaxkeypair"
  associate_public_ip_address = true
  user_data                   = filebase64("${path.module}/scripts/user_data.sh")
  instance_profile            = aws_iam_instance_profile.iam_instance_profile.name
  subnet_id                   = module.public_subnets.subnets[0].id
  security_groups             = [module.security_group.id]
}

# API Gateway configuration
resource "aws_api_gateway_rest_api" "mediaconvert_rest_api" {
  name = "mediaconvert-api"
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
  stage_name    = "dev"
}