# EventBridge Rule Configuration
resource "aws_cloudwatch_event_rule" "mediaconvert-job-state-change-rule" {
  name        = "mediaconvert-job-state-change-rule"
  description = "It monitors the media convert job state change event"
  event_pattern = jsonencode({
    source = [
      "aws.mediaconvert"
    ]
    detail-type = [
      "MediaConvert Job State Change"
    ]
  })
  tags = {
    Name = var.application_name
  }
}

# EventBridge Target Configuration
resource "aws_cloudwatch_event_target" "mediaconvert-eventbridge-target" {
  rule      = aws_cloudwatch_event_rule.mediaconvert-job-state-change-rule.name
  target_id = "MediaConvertJobStateChange"
  arn       = aws_sns_topic.mediaconvert-sns-topic.arn
}
