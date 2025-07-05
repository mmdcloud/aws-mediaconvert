output "api_gateway_url" {
  value = aws_api_gateway_deployment.mediaconvert_api_deployment.invoke_url
}

output "frontend_url" {
  value = module.mediaconvert_frontend_instance.public_ip
}