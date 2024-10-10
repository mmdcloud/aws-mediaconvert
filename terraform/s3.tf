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

resource "aws_s3_bucket" "mediaconvert-function-code" {
  bucket        = "theplayer007-mediaconvert-function-code"
  force_destroy = true
  tags = {
    Name = "theplayer007-mediaconvert-function-code"
  }
}

resource "aws_s3_bucket_versioning" "mediaconvert-function-code-versioning" {
  bucket = aws_s3_bucket.mediaconvert-function-code.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket" "mediaconvert-function-code-signed" {
  bucket        = "theplayer007-mediaconvert-function-code-signed"
  force_destroy = true
  tags = {
    Name = "theplayer007-mediaconvert-function-code-signed"
  }
}

resource "aws_s3_object" "mediaconvert-function-code-object" {
  bucket = aws_s3_bucket.mediaconvert-function-code.id
  key    = "convert_function.zip"
  source = "./files/convert_function.zip"
}
