terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # State is stored locally by default and git-ignored (*.tfstate).
  # For shared/team use, switch to a remote S3 backend:
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "aws-deployment-pipeline/terraform.tfstate"
  #   region         = "ap-south-1"
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "aws-deployment-pipeline"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
