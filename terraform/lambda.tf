# Lambda function configuration
resource "aws_lambda_function" "mediaconvert-function" {
  function_name = "mediaconvert-function"
  role          = aws_iam_role.mediaconvert-function-role.arn
  handler       = "convert_function.lambda_handler"
  runtime       = "python3.10"
  depends_on    = [aws_iam_role_policy_attachment.mediaconvert-function-policy-attachment]
  s3_bucket     = aws_s3_bucket.mediaconvert-function-code.bucket
  s3_key        = "convert_function.zip"
  environment {
    variables = {
      DestinationBucket = aws_s3_bucket.mediaconvert-destination.bucket
      MediaConvertRole  = aws_iam_role.mediaconvert-role.arn
    }
  }
  code_signing_config_arn = aws_lambda_code_signing_config.mediaconvert_signing_config.arn
  tags = {
    Name = var.application_name
  }
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

# Lambda function for getting DynamoDB records
resource "aws_lambda_function" "get-records-function" {
  filename      = "./files/get_records.zip"
  function_name = "get-records-function"
  role          = aws_iam_role.mediaconvert-function-role.arn
  handler       = "get_records.lambda_handler"
  runtime       = "python3.10"
  depends_on    = [aws_iam_role_policy_attachment.mediaconvert-function-policy-attachment]
  # code_signing_config_arn = aws_lambda_code_signing_config.mediaconvert_signing_config.arn
  tags = {
    Name = var.application_name
  }
}

# Lambda function for generating presigned url for uploading media files
resource "aws_lambda_function" "mediaconvert-generate-presigned-url" {
  filename      = "./files/get_presigned_url.zip"
  function_name = "mediaconvert-generate-presigned-url"
  role          = aws_iam_role.mediaconvert-function-role.arn
  handler       = "get_presigned_url.lambda_handler"
  runtime       = "python3.10"
  depends_on    = [aws_iam_role_policy_attachment.mediaconvert-function-policy-attachment]
  # code_signing_config_arn = aws_lambda_code_signing_config.mediaconvert_signing_config.arn
  tags = {
    Name = var.application_name
  }
}
