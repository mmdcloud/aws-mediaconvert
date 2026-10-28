output "bucket" {
  value = aws_s3_bucket.bucket.bucket
}
output "arn" {
  value = aws_s3_bucket.bucket.arn
}
output "objects" {
  value = aws_s3_object.object[*]
}
output "bucket_regional_domain_name" {
  value = aws_s3_bucket.bucket.bucket_regional_domain_name
}
