# DynamoDB Table For storing media records
resource "aws_dynamodb_table" "mediaconvert-records" {
  name           = "records"
  billing_mode   = "PROVISIONED"
  read_capacity  = 20
  write_capacity = 20
  hash_key       = "RecordId"
  range_key      = "filename"

  attribute {
    name = "RecordId"
    type = "S"
  }

  attribute {
    name = "filename"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = true
  }

  tags = {
    Name = "mediaconvert-records"
  }
}
