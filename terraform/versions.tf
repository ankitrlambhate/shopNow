terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Remote state in S3 with DynamoDB locking.
  # Bucket/table values are supplied at init time by the Jenkins job:
  #   terraform init -backend-config="bucket=..." -backend-config="dynamodb_table=..." -backend-config="region=..."
  backend "s3" {
    key     = "shopnow/terraform.tfstate"
    encrypt = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
