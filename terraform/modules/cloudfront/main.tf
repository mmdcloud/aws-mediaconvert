# Origin Access Control for Cloudfront Distribution
resource "aws_cloudfront_origin_access_control" "origin_access_control" {
  name                              = var.oac_name
  description                       = var.oac_description
  origin_access_control_origin_type = var.oac_origin_access_control_origin_type
  signing_behavior                  = var.oac_signing_behavior
  signing_protocol                  = var.oac_signing_protocol
}

# Configuring cloudfront distribution configuration
resource "aws_cloudfront_distribution" "distribution" {
  enabled = var.enabled
  dynamic "origin" {
    for_each = var.origin
    content {
      origin_id                = origin.value["origin_id"]
      origin_access_control_id = aws_cloudfront_origin_access_control.origin_access_control.id
      domain_name              = origin.value["domain_name"]
      connection_attempts      = origin.value["connection_attempts"]
      connection_timeout       = origin.value["connection_timeout"]
    }
  }
  default_cache_behavior {
    compress         = var.compress
    smooth_streaming = var.smooth_streaming
    target_origin_id = var.target_origin_id
    allowed_methods  = var.allowed_methods
    cached_methods   = var.cached_methods
    forwarded_values {
      query_string = var.query_string
      cookies {
        forward = var.forward_cookies
      }
    }
    viewer_protocol_policy = var.viewer_protocol_policy
    min_ttl                = var.min_ttl
    default_ttl            = var.default_ttl
    max_ttl                = var.max_ttl
  }
  restrictions {
    geo_restriction {
      restriction_type = var.geo_restriction_type
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = var.cloudfront_default_certificate
  }
  price_class = var.price_class
  tags = {
    Name = var.distribution_name
  }
}
