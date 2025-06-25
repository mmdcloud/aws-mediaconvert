# EventBridge Rule Configuration
resource "aws_cloudwatch_event_rule" "rule" {
  name          = var.rule_name
  description   = var.rule_description
  event_pattern = var.event_pattern
  tags = {
    Name = var.rule_name
  }
}

# EventBridge Target Configuration
resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.rule.name
  target_id = var.target_id
  arn       = var.target_arn
}
