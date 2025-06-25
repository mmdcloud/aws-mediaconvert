variable "oac_name" {
  type = string
}
variable "oac_description" {
  type = string
}
variable "oac_origin_access_control_origin_type" {
  type = string
}
variable "oac_signing_behavior" {
  type = string
}
variable "oac_signing_protocol" {
  type = string
}
variable "enabled" {}
variable "distribution_name" {
  
}
variable "origin" {
  type = list(object({
    origin_id                = string
    domain_name              = string
    connection_attempts      = number
    connection_timeout       = number
  }))
}
variable "compress" {
    type = bool
}
variable "smooth_streaming" {
    type = bool
}
variable "target_origin_id" {
    type = string
}
variable "allowed_methods" {
    type = list(string)
}
variable "cached_methods" {
    type = list(string)
}
variable "viewer_protocol_policy" {}
variable "min_ttl" {}
variable "default_ttl" {}
variable "max_ttl" {}
variable "cloudfront_default_certificate" {}
variable "price_class" {}
variable "query_string" {}
variable "forward_cookies" {}
variable "geo_restriction_type" {}