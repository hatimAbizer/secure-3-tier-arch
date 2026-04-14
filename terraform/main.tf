# ============================================================
# main.tf
# ============================================================
# This is the ENTRY POINT of every Terraform project.
# It tells Terraform two things:
#   1. Which PROVIDERS to use (AWS in our case)
#   2. Which VERSION of those providers to download
#
# Think of providers as plugins. Terraform itself doesn't
# know how to talk to AWS — the AWS provider does.
# ============================================================

terraform {
  # required_version pins the Terraform CLI version.
  # The ~> operator means "1.0 or higher, but not 2.0"
  # This prevents someone with an older Terraform from
  # accidentally running your code and getting errors.
  required_version = "~> 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws" # Official AWS provider from HashiCorp
      version = "~> 5.0"        # AWS provider v5.x
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
      # We use this to generate a random DB password
      # so we never hardcode secrets in our code
    }
  }
}

# ============================================================
# PROVIDER CONFIGURATION
# ============================================================
# This block configures the AWS provider.
# It tells Terraform WHICH AWS region to deploy into
# and WHERE to get credentials.
#
# CREDENTIALS: Terraform uses your local AWS CLI credentials.
# Run `aws configure` before running terraform.
# Never put your access key / secret key here — that's a
# serious security mistake.
# ============================================================

provider "aws" {
  region = var.aws_region # Region comes from variables.tf
  
  # default_tags applies these tags to EVERY resource
  # automatically. This is a best practice — it means
  # every resource in AWS console shows what project
  # and environment it belongs to.
  default_tags {
    tags = {
      Project     = "secure-3tier-app"
      Environment = "dev"
      ManagedBy   = "terraform"
    }
  }
}

provider "random" {
  # No configuration needed for the random provider
}
