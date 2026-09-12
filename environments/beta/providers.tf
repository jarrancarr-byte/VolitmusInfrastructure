provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "VoltimusMaximus"
      ManagedBy   = "Terraform"
      Environment = "beta"
    }
  }
}

# Cognito custom-domain certificates must be in us-east-1 regardless of
# the region of the user pool.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = {
      Project     = "VoltimusMaximus"
      ManagedBy   = "Terraform"
      Environment = "beta"
    }
  }
}

# Authentication comes from CLOUDFLARE_API_TOKEN.
provider "cloudflare" {}
