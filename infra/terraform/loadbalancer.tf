# loadbalancer.tf
# ├── ALB 본체
# ├── Target Group (Blue/Green)
# ├── Listener 80 → Blue/Green 포워딩 (HTTP)
# └── [비활성화] Route53, ACM, HTTPS 443 리스너 — 도메인 미설정 환경에서 비활성화

data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}."
  private_zone = false
}

data "aws_acm_certificate" "issued_cert" {
  domain   = "${var.domain_name}"
  statuses = ["ISSUED"]
  most_recent = true
}

# 1. ALB 본체
resource "aws_lb" "web_alb" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
  tags               = { Name = "${var.project_name}-alb" }
}

# ─── Blue Target Group ───────────────────────────────────────────
resource "aws_lb_target_group" "blue_tg" {
  name     = "${var.project_name}-blue-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }
}

# ─── Green Target Group ──────────────────────────────────────────
resource "aws_lb_target_group" "green_tg" {
  name     = "${var.project_name}-green-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    path                = "/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = { Name = "${var.project_name}-green-tg" }
}

# ─── HTTP 80 리스너 — Blue 100% / Green 0% (블루그린 전환용) ─────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = data.aws_acm_certificate.issued_cert.arn

  default_action {
    type = "forward"
    forward {
      target_group {
        arn    = aws_lb_target_group.blue_tg.arn
        weight = 100
      }
      target_group {
        arn    = aws_lb_target_group.green_tg.arn
        weight = 0
      }
    }
  }
}
