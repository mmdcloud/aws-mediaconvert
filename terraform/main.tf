locals {
  dest_bucket_origin_id   = "${var.destination_bucket}-origin"
  dest_bucket_domain_name = "${var.destination_bucket}.s3.${var.region}.amazonaws.com"
}

# SNS Topic for notifying users about the state changes in MediaConvert Job
resource "aws_sns_topic" "mediaconvert-sns-topic" {
  name = "mediaconvert-sns-topic"
  tags = {
    Name = var.application_name
  }
}

# SNS Subscription
resource "aws_sns_topic_subscription" "mediaconvert-sns-subscription" {
  topic_arn = aws_sns_topic.mediaconvert-sns-topic.arn
  protocol  = "email"
  endpoint  = "mohitfury1997@gmail.com"
}

# EventBridge Rule Configuration
resource "aws_cloudwatch_event_rule" "mediaconvert-job-state-change-rule" {
  name        = "mediaconvert-job-state-change-rule"
  description = "It monitors the media convert job state change event"
  event_pattern = jsonencode({
    source = [
      "aws.mediaconvert"
    ]
    detail-type = [
      "MediaConvert Job State Change"
    ]
  })
  tags = {
    Name = var.application_name
  }
}

# EventBridge Target Configuration
resource "aws_cloudwatch_event_target" "mediaconvert-eventbridge-target" {
  rule      = aws_cloudwatch_event_rule.mediaconvert-job-state-change-rule.name
  target_id = "MediaConvertJobStateChange"
  arn       = aws_sns_topic.mediaconvert-sns-topic.arn
}

# EventBridge SNS Topic Policy
data "aws_iam_policy_document" "mediaconvert-sns-topic-policy" {
  statement {
    effect  = "Allow"
    actions = ["SNS:Publish"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    resources = [aws_sns_topic.mediaconvert-sns-topic.arn]
  }
}

resource "aws_sns_topic_policy" "mediaconvert-sns-eventbridge-permission-policy" {
  arn    = aws_sns_topic.mediaconvert-sns-topic.arn
  policy = data.aws_iam_policy_document.mediaconvert-sns-topic-policy.json
}

# S3 bucket for media convert upload
resource "aws_s3_bucket" "mediaconvert-source" {
  bucket        = var.source_bucket
  force_destroy = true
  tags = {
    Name = var.application_name
  }
}

# S3 bucket to store converted media assets
resource "aws_s3_bucket" "mediaconvert-destination" {
  bucket        = var.destination_bucket
  force_destroy = true
  tags = {
    Name = var.application_name
  }
}

# MediaConvert role to call S3 APIs on your behalf.
resource "aws_iam_role" "mediaconvert-role" {
  name               = "mediaconvert-role"
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
  tags = {
    Name = var.application_name
  }
}

# MediaConvert policy to call S3 APIs on your behalf.
resource "aws_iam_policy" "mediaconvert-policy" {
  name   = "mediaconvert-policy"
  policy = <<EOF
    {
      "Version": "2012-10-17",
      "Statement": [
        {
        "Effect": "Allow",
        "Action": [
                "s3:*",
                "s3-object-lambda:*"	
            ],
            "Resource": "*"
        }
      ]
    }
    EOF
  tags = {
    Name = var.application_name
  }
}

# MediaConvert policy attachment to call S3 APIs on your behalf.
resource "aws_iam_role_policy_attachment" "mediaconvert-role-policy-attachment" {
  role       = aws_iam_role.mediaconvert-role.name
  policy_arn = aws_iam_policy.mediaconvert-policy.arn
}

# Lambda Function Role
resource "aws_iam_role" "mediaconvert-function-role" {
  name               = "mediaconvert-function-role"
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
  tags = {
    Name = var.application_name
  }
}

# Lambda Function Policy
resource "aws_iam_policy" "mediaconvert-function-policy" {
  name        = "mediaconvert-function-policy"
  description = "AWS IAM Policy for managing aws lambda role"
  policy      = <<EOF
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
          }
      ]
    }
    EOF
  tags = {
    Name = var.application_name
  }
}

# Lambda Function Role-Policy Attachment
resource "aws_iam_role_policy_attachment" "mediaconvert-function-policy-attachment" {
  role       = aws_iam_role.mediaconvert-function-role.name
  policy_arn = aws_iam_policy.mediaconvert-function-policy.arn
}

# Granting invocation permission to s3 for lambda
resource "aws_lambda_permission" "mediaconvert-function-s3-invocation-permission" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.mediaconvert-function.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.mediaconvert-source.arn
}

# Specifying bucket and function configuration for the trigger
resource "aws_s3_bucket_notification" "mediaconvert-bucket-notification" {
  bucket = aws_s3_bucket.mediaconvert-source.bucket
  lambda_function {
    lambda_function_arn = aws_lambda_function.mediaconvert-function.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.mediaconvert-function-s3-invocation-permission]
}

# Lambda function configuration
resource "aws_lambda_function" "mediaconvert-function" {
  filename      = "lambda_function.zip"
  function_name = "mediaconvert-function"
  role          = aws_iam_role.mediaconvert-function-role.arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.10"
  depends_on    = [aws_iam_role_policy_attachment.mediaconvert-function-policy-attachment]
  environment {
    variables = {
      DestinationBucket = aws_s3_bucket.mediaconvert-destination.bucket
      MediaConvertRole  = aws_iam_role.mediaconvert-role.arn
    }
  }
  tags = {
    Name = var.application_name
  }
}

# Origin Access Control for Cloudfront Distribution
resource "aws_cloudfront_origin_access_control" "mediaconvert-s3-oac" {
  name                              = "mediaconvert-s3-oac"
  description                       = "mediaconvert-s3-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# Configuring Cloudfront CDN for media file delivery
resource "aws_cloudfront_distribution" "mediaconvert_cloudfront_distribution" {
  enabled = true
  origin {
    origin_id                = local.dest_bucket_origin_id
    origin_access_control_id = aws_cloudfront_origin_access_control.mediaconvert-s3-oac.id
    domain_name              = local.dest_bucket_domain_name
    connection_attempts      = 3
    connection_timeout       = 10
  }
  default_cache_behavior {
    compress         = true
    smooth_streaming = false
    target_origin_id = local.dest_bucket_origin_id
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    forwarded_values {
      query_string = true
      cookies {
        forward = "all"
      }
    }
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  price_class     = "PriceClass_200"
  is_ipv6_enabled = false
  tags = {
    Name = var.application_name
  }
}

# MediaConvert Destination Bucket to Cloudfront Access Policy
resource "aws_s3_bucket_policy" "mediaconvert_destination_s3_bucket_policy" {
  bucket = aws_s3_bucket.mediaconvert-destination.id
  policy = jsonencode({
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
        "Resource" : "${aws_s3_bucket.mediaconvert-destination.arn}/*",
        "Condition" : {
          "StringEquals" : {
            "AWS:SourceArn" : "${aws_cloudfront_distribution.mediaconvert_cloudfront_distribution.arn}"
          }
        }
      }
    ]
  })
}
