# loadbalancer.tf
# ├── ALB 본체
# ├── Target Group
# ├── Listener (80, 443)
# └── Route53 레코드

data "aws_route53_zone" "selected" {
  name         = "${var.domain_name}." # 도메인 이름 끝에 점(.)을 붙여야 합니다.
  private_zone = false
}

# 만들어진 ACM 인증서 가져오기
data "aws_acm_certificate" "issued_cert" {
  domain   = "*.${var.domain_name}"
  statuses = ["ISSUED"]
  most_recent = true
}


# 1. ALB 본체 (Load Balancer L7)
resource "aws_lb" "web_alb" {
    name = "${var.project_name}-alb"
    internal = false # 외부 노출용
    load_balancer_type = "application" # 로드벨러서 종류
    security_groups = [aws_security_group.alb_sg.id] # 위에서 정의한 보안그룹 적용
    # 고가용성 을 위해 최소 2개의 public subnet 을 제공해야 한다.
    subnets = [aws_subnet.public_subnet_1.id, aws_subnet.public_subnet_2.id]
    # tag
    tags = {
      Name = "${var.project_name}-alb"
    }
}


# 3. ALB 가 받은 요청을 최종적으로 전달할 대상그룹(ASG이 자동 등록)
# ─── Blue Target Group ───────────────────────────────────────────
resource "aws_lb_target_group" "blue_tg" {
    name = "${var.project_name}-blue-tg"
    # 대상 ec2 에서 돌아가는 web 서버의 port 번호(변경가능)
    port = 80
    protocol = "HTTP"
    vpc_id = aws_vpc.main.id
    # 헬스 체크: 로드밸런서가 각 EC2에게 "너 살아있니?"라고 주기적으로 물어보는 설정입니다.
    # 아래의 설정은 health_check 를 생략했을때 적용되는 default 옵션입니다.
    health_check {
        enabled             = true           # 헬스 체크 기능을 활성화합니다.
        path                = "/health"            # EC2의 어느 경로로 접속해서 확인할지 결정합니다. (/ ->/health로 변경)
        port                = "traffic-port" # 위에서 설정한 80포트를 그대로 사용하여 확인합니다.
        protocol            = "HTTP"         # 상태 확인 시 사용할 통신 규약입니다.
        # [판단 기준]
        healthy_threshold   = 2  # 연속 2번 성공하면 "이 친구 건강하네!"라고 판단 (서비스 투입)
        unhealthy_threshold = 2  # 연속 2번 실패하면 "이 친구 아프네?"라고 판단 (서비스 제외)
        # [시간 설정]
        timeout             = 5  # 응답을 기다리는 최대 시간(초). 이 시간 넘기면 실패로 간주합니다.
        interval            = 30 # 다음 확인까지 기다리는 주기(초). 너무 짧으면 서버에 부담을 줍니다.
        matcher             = "200"  # 200 OK만 정상으로 판단
    }    
}
# ─── Green Target Group ───────────────────────────────────────────
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

# ALB 80 port -> 443 port 로 리다이렉트
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "80"
  protocol          = "HTTP"
  # 443 port 로 리다이렉트 이동시키는 설정
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


# ─── HTTPS Listener 수정 (Blue가 기본, Green은 가중치 0) ──────────
# ALB 443 리스너
resource "aws_lb_listener" "https" {
  # 이 리스너가 설치될 로드밸런서(ALB)의 고유 주소(ARN)를 지정
  load_balancer_arn = aws_lb.web_alb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" #최신 보안 정책 변경
  
  # route53.tf 에서 만든 인증서의 arn (직접 발급받아서 사용할꺼면 아래의 코드)
  # certificate_arn   = aws_acm_certificate_validation.cert.certificate_arn

  # 여기에서는 route53.tf 를 실행하지 않고 미리 발급받은 인증서의 arn 을 사용한다 ######### data변수 잠시 보류?
  certificate_arn = data.aws_acm_certificate.issued_cert.arn

  # 기본 동작: 443번 포트로 요청이 들어왔을 때 무엇을 할 것인가?
  default_action {
    type             = "forward"
    # "443번으로 들어온 손님은 blue_tg에 담긴 EC2들에게 보내라!"는 명령
    forward {
      target_group {
        arn    = aws_lb_target_group.blue_tg.arn
        weight = 100  # Blue가 100% 트래픽
      }
      target_group {
        arn    = aws_lb_target_group.green_tg.arn
        weight = 0    # Green은 대기 중
      }
    }
  }
}


