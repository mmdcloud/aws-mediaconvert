output "arn" {
  value = aws_cloudfront_distribution.distribution.arn
}

output "domain_name" {
  value = aws_cloudfront_distribution.distribution.domain_name
}
