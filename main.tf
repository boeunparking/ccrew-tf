terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0"
    }
  }
}

# 서울 리전 (기본 provider)
provider "aws" {
  region = var.region_seoul
}

# 도쿄 리전 (alias provider)
provider "aws" {
  alias  = "tokyo"
  region = var.region_tokyo
}


### 서울 인프라 ###
module "seoul" {
  source = "./modules/region_stack"

  region         = var.region_seoul
  vpc_cidr_block = var.vpc_cidr_seoul
  pjt_prefix     = "seoul"
  subnets        = var.subnets_seoul
}


### 도쿄 인프라 ###
module "tokyo" {
  source = "./modules/region_stack"
  providers = {
    aws = aws.tokyo
  }

  region         = var.region_tokyo
  vpc_cidr_block = var.vpc_cidr_tokyo
  pjt_prefix     = "tokyo"
  subnets        = var.subnets_tokyo
}
