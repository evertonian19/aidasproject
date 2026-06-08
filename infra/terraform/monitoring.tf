# monitoring.tf
# ├── CloudWatch Log Groups
# ├── CloudWatch Metric Alarms (CPU, ALB)
# └── SNS Topic (알림 채널)

# ─── 1. SNS Topic (알람 → Lambda/Slack 연결 준비) ─────────────────
resource "aws_sns_topic" "alarm_topic" {
  name = "${var.project_name}-alarm-topic"
  tags = { Name = "${var.project_name}-alarm-topic" }
}

# ─── 2. CloudWatch Log Groups ─────────────────────────────────────
# ASG 인스턴스 로그
resource "aws_cloudwatch_log_group" "asg_logs" {
  name              = "/aws/asg/${var.project_name}"
  retention_in_days = 14
  tags              = { Name = "${var.project_name}-asg-logs" }
}

# Tailscale EC2 로그
resource "aws_cloudwatch_log_group" "ec2_logs" {
  name              = "/aws/ec2/${var.project_name}"
  retention_in_days = 14
  tags              = { Name = "${var.project_name}-ec2-logs" }
}

# Lambda 로그 (lambda.tf 생성 전 미리 선언)
resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.project_name}-slack-alert"
  retention_in_days = 14
  tags              = { Name = "${var.project_name}-lambda-logs" }
}

# ─── 3. ASG CPU 알람 ──────────────────────────────────────────────
# CPU 높을 때 (Scale Out 트리거 + 알림)
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.project_name}-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 80  # 80% 초과 시 위험 알림 (ASG 스케일링은 50%에서 별도 동작)
  alarm_description   = "ASG CPU 사용률 80% 초과"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
  ok_actions          = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  tags = { Name = "${var.project_name}-cpu-high" }
}

# CPU 낮을 때 (Scale In 모니터링)
resource "aws_cloudwatch_metric_alarm" "cpu_low" {
  alarm_name          = "${var.project_name}-cpu-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 10  # 10% 미만 시 알림
  alarm_description   = "ASG CPU 사용률 10% 미만"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.asg.name
  }

  tags = { Name = "${var.project_name}-cpu-low" }
}

# ─── 4. ALB 알람 ──────────────────────────────────────────────────
# ALB 5xx 에러율 알람
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${var.project_name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 10  # 1분에 10건 초과 시 알림
  treat_missing_data  = "notBreaching"
  alarm_description   = "ALB 5xx 에러 10건 초과"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    LoadBalancer = aws_lb.web_alb.arn_suffix
  }

  tags = { Name = "${var.project_name}-alb-5xx" }
}

# ALB Unhealthy Host 알람
resource "aws_cloudwatch_metric_alarm" "alb_unhealthy_host" {
  alarm_name          = "${var.project_name}-unhealthy-host"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0  # Unhealthy 호스트 1개라도 생기면 알림
  treat_missing_data  = "notBreaching"
  alarm_description   = "ALB Unhealthy 호스트 발생"
  alarm_actions       = [aws_sns_topic.alarm_topic.arn]
  ok_actions          = [aws_sns_topic.alarm_topic.arn]

  dimensions = {
    LoadBalancer = aws_lb.web_alb.arn_suffix
    TargetGroup  = aws_lb_target_group.web_tg.arn_suffix
  }

  tags = { Name = "${var.project_name}-unhealthy-host" }
}

# ─── 5. CloudWatch Dashboard ──────────────────────────────────────
resource "aws_cloudwatch_dashboard" "main" {
  dashboard_name = "${var.project_name}-dashboard"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        properties = {
          region = "ap-northeast-2"    # 추가
          title  = "ASG CPU 사용률"
          period = 60
          metrics = [
            ["AWS/EC2", "CPUUtilization", "AutoScalingGroupName", aws_autoscaling_group.asg.name]
          ]
          view  = "timeSeries"
          stat  = "Average"
        }
      },
      {
        type = "metric"
        properties = {
          region = "ap-northeast-2"    # 추가
          title  = "ALB 요청 수 & 에러율"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount",                "LoadBalancer", aws_lb.web_alb.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_5XX_Count",   "LoadBalancer", aws_lb.web_alb.arn_suffix],
            ["AWS/ApplicationELB", "HTTPCode_Target_4XX_Count",   "LoadBalancer", aws_lb.web_alb.arn_suffix]
          ]
          view = "timeSeries"
          stat = "Sum"
        }
      },
      {
        type = "metric"
        properties = {
          region = "ap-northeast-2"    # 추가
          title  = "ALB Healthy / Unhealthy 호스트 수"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount",   "LoadBalancer", aws_lb.web_alb.arn_suffix, "TargetGroup", aws_lb_target_group.web_tg.arn_suffix],
            ["AWS/ApplicationELB", "UnHealthyHostCount", "LoadBalancer", aws_lb.web_alb.arn_suffix, "TargetGroup", aws_lb_target_group.web_tg.arn_suffix]
          ]
          view = "timeSeries"
          stat = "Maximum"
        }
      }
    ]
  })
}

