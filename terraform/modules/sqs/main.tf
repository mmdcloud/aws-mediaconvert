# Create the Dead Letter Queue (DLQ)
resource "aws_sqs_queue" "dead_letter_queue" {
  name                      = var.dlq_name
  message_retention_seconds = var.dlq_message_retention_seconds
}

# Create the main SQS queue with redrive policy
resource "aws_sqs_queue" "queue" {
  name                       = var.queue_name
  delay_seconds              = var.delay_seconds
  max_message_size           = var.max_message_size
  message_retention_seconds  = var.message_retention_seconds
  receive_wait_time_seconds  = var.receive_wait_time_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # Redrive policy (sends messages to DLQ after 5 failures)
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dead_letter_queue.arn
    maxReceiveCount     = var.dlq_max_receive_count
  })

  # Optional: Add server-side encryption
  sqs_managed_sse_enabled = var.sqs_managed_sse_enabled
}
