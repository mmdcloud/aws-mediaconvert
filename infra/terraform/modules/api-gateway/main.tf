resource "aws_api_gateway_rest_api" "api" {
  name = var.api_name
  endpoint_configuration {
    types = var.endpoint_types
  }
}

resource "aws_api_gateway_resource" "resources" {
  for_each    = var.resources
  rest_api_id = aws_api_gateway_rest_api.api.id
  parent_id   = each.value.parent == "root" ? aws_api_gateway_rest_api.api.root_resource_id : aws_api_gateway_resource.resources[each.value.parent].id
  path_part   = each.value_path_part
}

resource "aws_api_gateway_method" "methods" {
  for_each         = var.methods
  rest_api_id      = aws_api_gateway_rest_api.api.id
  resource_id      = aws_api_gateway_resource.resources[each.value.resource].id
  api_key_required = each.value.api_key_required
  http_method      = each.value.http_method
  authorization    = each.value.authorization
}

resource "aws_api_gateway_integration" "integrations" {
  for_each                = var.methods
  rest_api_id             = aws_api_gateway_rest_api.api.id
  resource_id             = aws_api_gateway_resource.resources[each.value.resource].id
  http_method             = each.value.http_method
  integration_http_method = each.value.http_method
  type                    = each.value.type
  credentials             = each.value.credentials
  uri                     = each.value.uri
  request_parameters      = each.value.request_parameters
  request_templates       = each.value.request_templates
}

# resource "aws_api_gateway_method_response" "method_response_200" {
#   rest_api_id = aws_api_gateway_rest_api.api.id
#   resource_id = aws_api_gateway_resource.resource.id
#   http_method = aws_api_gateway_method.method.http_method
#   status_code = "200"
# }

# resource "aws_api_gateway_integration_response" "integration_response_200" {
#   rest_api_id = aws_api_gateway_rest_api.api.id
#   resource_id = aws_api_gateway_resource.resource.id
#   http_method = aws_api_gateway_method.method.http_method
#   status_code = aws_api_gateway_method_response.method_response_200.status_code
#   depends_on = [
#     aws_api_gateway_integration.event-source-mapping-api-integration
#   ]
# }

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.api.id
  depends_on = [
    aws_api_gateway_integration.integrations
  ]
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_api_gateway_stage" "stage" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.api.id
  stage_name    = var.stage_name
}
