locals {
  dest_bucket_origin_id   = "${var.destination_bucket}-origin"
  dest_bucket_domain_name = "${var.destination_bucket}.s3.${var.region}.amazonaws.com"
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


