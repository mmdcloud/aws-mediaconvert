locals {
  endpoint = "mohitfury1997@gmail.com"
  protocol = "email"
}

# SNS Topic for notifying users about the state changes in MediaConvert Job
resource "aws_sns_topic" "mediaconvert-sns-topic" {
  name = "mediaconvert-sns-topic"
  tags = {
    Name = var.application_name
  }
}

# SNS Subscription
resource "aws_sns_topic_subscription" "mediaconvert-sns-subscription" {
  topic_arn = aws_sns_topic.mediaconvert-sns-topic.arn
  protocol  = local.protocol
  endpoint  = local.endpoint
}
