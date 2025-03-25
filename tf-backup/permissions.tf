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
                  "dynamodb:*"
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
