terraform {
  required_version = ">= 1.7"

  required_providers {
    # v6 is the first release where resources take a `region` argument,
    # which lets one module call cover many regions from a single provider.
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}
