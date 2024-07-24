variable "region" {
  type    = string
  default = "us-east-1"
}

variable "destination_bucket" {
  type    = string
  default = "theplayer007-mediaconvert-source"
}

variable "source_bucket" {
  type    = string
  default = "theplayer007-mediaconvert-destination"
}
