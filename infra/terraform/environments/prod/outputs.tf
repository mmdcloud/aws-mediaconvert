output "api_gateway_url" {
  value = aws_api_gateway_stage.mediaconvert_api_stage.invoke_url
}

output "frontend_url" {
  value = module.mediaconvert_frontend_cloudfront_distribution.domain_name
}
