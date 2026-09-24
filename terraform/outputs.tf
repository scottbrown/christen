output "role_arn" {
  description = "ARN of the IAM role the Lambda functions run as."
  value       = aws_iam_role.this.arn
}

output "function_arns" {
  description = "ARN of the Lambda function in each region, keyed by region."
  value       = { for region, fn in aws_lambda_function.this : region => fn.arn }
}

output "rule_arns" {
  description = "ARN of the EventBridge rule in each region, keyed by region."
  value       = { for region, rule in aws_cloudwatch_event_rule.this : region => rule.arn }
}
