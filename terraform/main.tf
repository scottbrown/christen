data "aws_region" "current" {}
data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  regions    = length(var.regions) > 0 ? var.regions : toset([data.aws_region.current.region])
  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
}

# handler.py is a copy of the inline handler in ../cfn-template.yml, which
# stays the source of truth.  CI fails if the two drift apart; see
# scripts/check_terraform_handler.py.
data "archive_file" "handler" {
  type        = "zip"
  source_file = "${path.module}/handler.py"
  output_path = "${path.module}/build/handler.zip"
}

resource "aws_iam_role" "this" {
  name = var.name
  path = "/lambda/"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ec2_naming" {
  name = "rw-add-ec2-tags"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # The EC2 Describe actions do not support resource-level
      # permissions, so "*" is the only resource they can be granted
      # on.  Both are read-only.
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeTags", "ec2:DescribeInstanceStatus"]
        Resource = "*"
      },
      # Writing is confined to the Name tag on instances in this
      # account.  Without the condition this role could overwrite any
      # tag on any instance, which is the same over-permission the
      # project exists to avoid granting to instance profiles.
      {
        Effect   = "Allow"
        Action   = "ec2:CreateTags"
        Resource = "arn:${local.partition}:ec2:*:${local.account_id}:instance/*"
        Condition = {
          "ForAllValues:StringEquals" = { "aws:TagKeys" = ["Name"] }
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name = "rw-cloudwatch-logs"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["logs:CreateLogStream", "logs:CreateLogGroup", "logs:PutLogEvents"]
      Resource = [for region in local.regions : "arn:${local.partition}:logs:${region}:${local.account_id}:*"]
    }]
  })
}

resource "aws_lambda_function" "this" {
  for_each = local.regions
  region   = each.value

  function_name    = var.name
  description      = "Names EC2 instances in an ASG based on its tags"
  role             = aws_iam_role.this.arn
  handler          = "handler.lambda_handler"
  runtime          = "python3.12"
  memory_size      = 128 # MB
  timeout          = 60  # seconds
  filename         = data.archive_file.handler.output_path
  source_code_hash = data.archive_file.handler.output_base64sha256
  tags             = var.tags

  environment {
    variables = {
      PROJECT_TAG_KEY     = var.project_tag_key
      ENVIRONMENT_TAG_KEY = var.environment_tag_key
      NAME_FORMAT         = var.name_format
    }
  }

  # The function can start before its policies are attached and fail its
  # first invocations for want of permissions.
  depends_on = [
    aws_iam_role_policy.ec2_naming,
    aws_iam_role_policy.cloudwatch_logs,
  ]
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.regions
  region   = each.value

  name        = var.name
  description = "Names EC2 instances in an ASG based on tags"
  state       = "ENABLED"
  tags        = var.tags

  event_pattern = jsonencode({
    source      = ["aws.autoscaling"]
    detail-type = ["EC2 Instance Launch Successful"]
  })
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.regions
  region   = each.value

  rule      = aws_cloudwatch_event_rule.this[each.key].name
  target_id = "lambda-name-instance"
  arn       = aws_lambda_function.this[each.key].arn
}

resource "aws_lambda_permission" "this" {
  for_each = local.regions
  region   = each.value

  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.this[each.key].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.this[each.key].arn
}
