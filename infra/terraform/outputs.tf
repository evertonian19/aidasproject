# [Terraform 출력] 인프라 생성이 완료된 후 화면에 보여줄 생성된 EC2의 퍼블릭 IP, ALB 주소 등을 지정하는 파일입니다.
# outputs.tf
# ├── Network
# ├── EC2 (Tailscale, nat_ec2_a, nat_ec2_c)
# ├── ALB
# ├── CloudFront
# ├── DynamoDB
# ├── Lambda
# └── Monitoring

# ─── Network ──────────────────────────────────────────────────────
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "퍼블릭 서브넷 ID 목록"
  value       = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
}

output "private_subnet_ids" {
  description = "프라이빗 서브넷 ID 목록"
  value       = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
}

# ─── EC2 (Tailscale) ──────────────────────────────────────────────
output "instance_private_ip" {
  description = "Tailscale EC2 Private IP"
  value       = aws_instance.my_ec2.private_ip
}

# NAT EC2의 퍼블릭 IP 출력──────────────────────────────────────────────
output "nat_ec2_a_ip" {
  value = aws_eip.nat_ec2_a_eip.public_ip  # EIP 참조
}

output "nat_ec2_c_ip" {
  value = aws_eip.nat_ec2_c_eip.public_ip  # EIP 참조
}
# ─── ASG ──────────────────────────────────────────────────────────
#  교체
output "asg_blue_name" {
  description = "Blue ASG 이름"
  value       = aws_autoscaling_group.asg_blue.name
}

output "asg_green_name" {
  description = "Green ASG 이름"
  value       = aws_autoscaling_group.asg_green.name
}


# ─── ALB ──────────────────────────────────────────────────────────
output "alb_dns_name" {
  description = "ALB DNS 주소"
  value       = aws_lb.web_alb.dns_name
}

output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.web_alb.arn
}


# ─── CloudFront ───────────────────────────────────────────────────
output "cloudfront_domain" {
  value = aws_cloudfront_distribution.main.domain_name
}
output "cloudfront_id" {
  value = aws_cloudfront_distribution.main.id
}
output "s3_bucket_name" {
  value = aws_s3_bucket.assets.bucket
}

# ─── DynamoDB ─────────────────────────────────────────────────────
output "incident_table_name" {
  description = "장애 이력 DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.incident_table.name
}

output "incident_table_arn" {
  description = "장애 이력 DynamoDB 테이블 ARN"
  value       = aws_dynamodb_table.incident_table.arn
}

output "runbook_table_name" {
  description = "Runbook DynamoDB 테이블 이름"
  value       = aws_dynamodb_table.runbook_table.name
}

# ─── Lambda ───────────────────────────────────────────────────────
output "lambda_function_arn" {
  description = "Slack 알림 Lambda ARN"
  value       = aws_lambda_function.slack_alert.arn
}

output "lambda_function_name" {
  description = "Slack 알림 Lambda 이름 (수동 테스트 시 필요)"
  value       = aws_lambda_function.slack_alert.function_name
}

# ─── Monitoring ───────────────────────────────────────────────────
output "sns_topic_arn" {
  description = "알람 SNS Topic ARN"
  value       = aws_sns_topic.alarm_topic.arn
}

output "cloudwatch_dashboard_url" {
  description = "CloudWatch 대시보드 URL"
  value       = "https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
}

# ─── 접속 정보 요약 ───────────────────────────────────────────────
output "service_endpoints" {
  description = "서비스 접속 주소 요약"
  value = {
    alb        = "http://${aws_lb.web_alb.dns_name}"
    dashboard  = "https://ap-northeast-2.console.aws.amazon.com/cloudwatch/home?region=ap-northeast-2#dashboards:name=${aws_cloudwatch_dashboard.main.dashboard_name}"
    cloudfront = "https://${aws_cloudfront_distribution.main.domain_name}"
    domain     = "https://${var.domain_name}"
  }
}