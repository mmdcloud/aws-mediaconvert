variable "name" {}
variable "billing_mode" {}
variable "read_capacity" {}
variable "write_capacity" {}
variable "hash_key" {}
variable "range_key" {}
variable "attributes" {
  type = list(object({
    name = string
    type = string
  }))
}
variable "ttl_attribute_name" {}
variable "ttl_attribute_enabled" {}