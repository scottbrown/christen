# Plan-only tests against a mocked AWS provider, so they need no
# credentials and create nothing.

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = { region = "us-east-1" }
  }
  mock_data "aws_partition" {
    defaults = { partition = "aws" }
  }
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
}

run "defaults_to_the_provider_region" {
  command = plan

  assert {
    condition     = keys(aws_lambda_function.this) == ["us-east-1"]
    error_message = "With no regions given, the function should be created only in the provider's region."
  }

  assert {
    condition     = aws_lambda_function.this["us-east-1"].environment[0].variables.NAME_FORMAT == "{project}-{environment}-{instance_id}"
    error_message = "The default name format should match the CloudFormation template's."
  }
}

run "fans_out_to_every_listed_region" {
  command = plan

  variables {
    regions = ["us-east-1", "eu-west-1", "ap-southeast-2"]
  }

  assert {
    condition     = length(aws_lambda_function.this) == 3 && length(aws_cloudwatch_event_rule.this) == 3 && length(aws_cloudwatch_event_target.this) == 3 && length(aws_lambda_permission.this) == 3
    error_message = "Each listed region should get its own function, rule, target and permission."
  }

  assert {
    condition     = aws_lambda_function.this["eu-west-1"].region == "eu-west-1"
    error_message = "Each function should be placed in the region it is keyed by."
  }

  assert {
    condition = toset(jsondecode(aws_iam_role_policy.cloudwatch_logs.policy).Statement[0].Resource) == toset([
      "arn:aws:logs:us-east-1:123456789012:*",
      "arn:aws:logs:eu-west-1:123456789012:*",
      "arn:aws:logs:ap-southeast-2:123456789012:*",
    ])
    error_message = "The shared role should be able to write logs in every listed region, and no other."
  }
}

run "create_tags_is_confined_to_the_name_tag" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.ec2_naming.policy).Statement[1].Condition["ForAllValues:StringEquals"]["aws:TagKeys"] == ["Name"]
    error_message = "ec2:CreateTags must be limited to the Name tag."
  }

  assert {
    condition     = jsondecode(aws_iam_role_policy.ec2_naming.policy).Statement[1].Resource == "arn:aws:ec2:*:123456789012:instance/*"
    error_message = "ec2:CreateTags must be limited to instances in this account."
  }
}

run "passes_tag_settings_to_the_function" {
  command = plan

  variables {
    project_tag_key     = "service"
    environment_tag_key = "stage"
    name_format         = "{environment}/{project}"
  }

  assert {
    condition = aws_lambda_function.this["us-east-1"].environment[0].variables == tomap({
      PROJECT_TAG_KEY     = "service"
      ENVIRONMENT_TAG_KEY = "stage"
      NAME_FORMAT         = "{environment}/{project}"
    })
    error_message = "The tag keys and name format should reach the function's environment."
  }
}
