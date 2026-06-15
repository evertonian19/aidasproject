# [Terraform 변수] AWS 리전 정보, 인스턴스 사양, 서브넷 대역 등 IaC 코드에서 공통으로 사용할 입력 변수들을 정의한 파일입니다.

# variables.tf
variable "project_name" { default = "aidas" }
variable "region" { default = "ap-northeast-2" }

variable "instance_type" { default = "t3.micro" }

# Auto Scaling 그룹에서 최소 및 최대 인스턴스 수
variable "max_size" { default = 4}
variable "min_size" { default = 0 }
# Auto Scaling 그룹에서 원하는 ec2 인스턴스 수
variable "desired_capacity" { default = 2 }

variable "vpc_cidr" { default = "10.0.0.0/16" }
variable "onpremise_cidr" { default = "172.16.8.0/24" }
variable "public_subnet_cidr1" { default = "10.0.1.0/24"}
variable "public_subnet_cidr2" { default = "10.0.3.0/24"}

variable "private_subnet_cidr1"{ default = "10.0.2.0/24"}
variable "private_subnet_cidr2" { default = "10.0.4.0/24"}

# 첫번째 ,두번째 가용영역
variable "avail_zone_1" { default = "ap-northeast-2a" }
variable "avail_zone_2" { default = "ap-northeast-2c" }

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
  default     = "aidas-key"
}

# 테일스케일 변수정의
variable "host_name" {
    type = string
    default = "aidas-server"
}

variable "tailnet_name" { type = string }

variable "tailscale_auth_key" {
    type = string
    sensitive = true
}

variable "tailscale_api_key" {
    type = string
    sensitive = true
}

variable "domain_name" {
  default = "everton.cloud"
}

variable "slack_webhook_url" {
  description = "Slack Incoming Webhook URL"
  type        = string
  sensitive   = true  # 플랜 출력에서 숨김
 
}
variable "github_token" {
  description = "GitHub Personal Access Token"
  type        = string
  sensitive   = true
}

variable "github_owner" {
  description = "GitHub 조직명"
  type        = string
  default     = "KT-TECHUP-AIDAS"
}

variable "aws_access_key" {
  description = "GitHub Actions용 AWS Access Key"
  type        = string
  sensitive   = true
}

variable "aws_secret_key" {
  description = "GitHub Actions용 AWS Secret Key"
  type        = string
  sensitive   = true
}

variable "dockerhub_username" {
  description = "Docker Hub 계정명"
  type        = string
}

variable "dockerhub_token" {
  description = "Docker Hub Access Token (Read & Write)"
  type        = string
  sensitive   = true
}

variable "db_url" {
  description = "FastAPI DB 연결 URL"
  type        = string
  sensitive   = true
}

variable "loki_url" {
  description = "Promtail이 로그를 푸시할 Loki endpoint URL"
  type        = string
  sensitive   = true
}
