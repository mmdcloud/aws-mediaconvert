resource "aws_api_gateway_rest_api" "my_api" {
  name = "my-api"
  description = "My API Gateway"

  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part = "mypath"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "lambda_integration" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  integration_http_method = "POST"
  type = "MOCK"
}

resource "aws_api_gateway_method_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"
}

resource "aws_api_gateway_integration_response" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.proxy.status_code

  depends_on = [
    aws_api_gateway_method.proxy,
    aws_api_gateway_integration.lambda_integration
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_integration.lambda_integration,
    aws_api_gateway_integration.options_integration, # Add this line
  ]

  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name = "dev"
}
