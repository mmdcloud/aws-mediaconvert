variable "api_name" {}
variable "stage_name" {}
variable "endpoint_types" {
  type = list(string)
}
variable "resources" {
  type = map(object({
    path_part = string
    parent    = string
  }))
}

variable "methods" {
  type = map(object({
    resource           = string
    api_key_required   = bool
    http_method        = string
    authorization      = string
    type               = string
    credentials        = string
    uri                = string
    request_parameters = map(string)
    request_templates  = map(string)
  }))
}
