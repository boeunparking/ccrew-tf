terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0" # ccrew-tf 와 동일 버전 고정
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # DevOps 결정사항: S3 + DynamoDB 락 (사실상 표준 조합)
  backend "s3" {
    bucket         = "cloud-duck-tfstate"
    key            = "cloud-duck/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "cloud-duck-tf-lock"
    encrypt        = true
  }
}

# 서울 리전 (Active)
provider "aws" {
  alias  = "seoul"
  region = "ap-northeast-2"

  default_tags {
    tags = {
      Project = "cloud-duck"
      Region  = "seoul-active"
      Managed = "terraform"
    }
  }
}

# 도쿄 리전 (Warm Standby / DR)
provider "aws" {
  alias  = "tokyo"
  region = "ap-northeast-1"

  default_tags {
    tags = {
      Project = "cloud-duck"
      Region  = "tokyo-standby"
      Managed = "terraform"
    }
  }
}
