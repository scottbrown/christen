variable "name" {
  description = "Name given to the IAM role and, in each region, the Lambda function and EventBridge rule. Change it only to run more than one copy of this module in the same account."
  type        = string
  default     = "asg-instance-namer"
}

variable "regions" {
  description = "Regions to deploy the rule and function into. Leave empty to use only the provider's region. The IAM role is global and is created once whatever this holds."
  type        = set(string)
  default     = []
}

variable "project_tag_key" {
  description = "The tag key read from the instance to supply the {project} placeholder. Change this if your tagging standard uses a different key, such as 'service' or 'app'."
  type        = string
  default     = "project"
}

variable "environment_tag_key" {
  description = "The tag key read from the instance to supply the {environment} placeholder, such as 'env' or 'stage'."
  type        = string
  default     = "environment"
}

variable "name_format" {
  description = "The format of the generated Name tag. The available placeholders are {project}, {environment} and {instance_id}, and they are roles rather than tag names: {project} is the value of whichever tag project_tag_key names. The instance ID has its 'i-' prefix stripped. The result is truncated to 255 characters, the AWS limit for a tag value."
  type        = string
  default     = "{project}-{environment}-{instance_id}"
}

variable "tags" {
  description = "Tags applied to every resource this module creates."
  type        = map(string)
  default     = {}
}
