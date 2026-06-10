# provider.tf
  
terraform {
  required_version = ">=1.14.0"
  required_providers {
    aws = {
        source = "hashicorp/aws"
        version = "~> 6.0"
    }
    # tailscale provider 추가
    tailscale = {
        source = "tailscale/tailscale" #정해진 약속어
        version = "~> 0.17"
     }
     tls = {
        source = "hashicorp/tls"
        version = "~> 4.0"
     }
     # GitHub provider 추가
    github = {
      source  = "integrations/github"
      version = "~> 6.0"
    }
  }
   # terraform 상태관리. 수동생성.
   backend "s3" {
     bucket       = "evertonian-aidas"
     key          = "prod/terraform.tfstate"
     region       = "ap-northeast-2"
     use_lockfile = true
     encrypt      = true
     profile      = "aidasProject2"
   }
  }

# 기본 provider (서울)
provider "aws" {
  region = var.region   
  profile = "aidasProject2" # AWS userID
}

# CloudFront ACM용 (버지니아 필수)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  profile = "aidasProject2" # AWS userID

}

provider "tailscale" {
  api_key = var.tailscale_api_key
  tailnet = var.tailnet_name
}

# GitHub provider 설정
provider "github" {
  token = var.github_token
  owner = var.github_owner
}

