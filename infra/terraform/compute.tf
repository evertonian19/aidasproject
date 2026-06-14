# compute.tf
# ├── ssh 키 페어 생성 (TLS 라이브러리 활용)
# ├── 최신 Amazon Linux 2023 AMI 조회
# ├── launch_template
# ├── asg_blue
# ├── asg_green
# └── 스케일링 정책 (blue/green)

# 1. SSH 키 페어 생성 (TLS 라이브러리 활용)
resource "tls_private_key" "pk" {
  algorithm = "RSA"
  rsa_bits  = 4096
}
resource "aws_key_pair" "kp" {
  key_name   = var.key_name
  public_key = tls_private_key.pk.public_key_openssh
}
resource "local_file" "ssh_key" {
  filename        = "${path.module}/${var.key_name}.pem"
  content         = tls_private_key.pk.private_key_pem
  file_permission = "0600"
}

# 2. 최신 Amazon Linux 2023 AMI 조회
data "aws_ami" "latest_al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# 3. ASG 런치 템플릿(ec2 설계도) 생성
resource "aws_launch_template" "lt" {
  name_prefix            = "${var.project_name}-asg-"                 # ec2 이름 접두사
  image_id               = data.aws_ami.latest_al2023.id  # 최신 Amazon Linux 2023 AMI 사용
  instance_type          = var.instance_type              # 변수로 인스턴스 타입 지정
  vpc_security_group_ids = [aws_security_group.asg_sg.id] # ASG 보안 그룹 연결
  key_name               = aws_key_pair.kp.key_name       # SSH 키 페어 연결
  iam_instance_profile {
  name = aws_iam_instance_profile.asg_profile.name
  }
  block_device_mappings {
  device_name = "/dev/xvda"
  ebs {
      volume_size = 40
      volume_type = "gp3"
    }
  }
user_data = base64encode(<<-EOF
#!/bin/bash

# 수집 타겟 로그 파일 경로 생성 및 권한 마킹
mkdir -p /var/log/apps
touch /var/log/apps/aidas-test.log
chmod 755 /var/log/apps
chmod 644 /var/log/apps/aidas-test.log

# 런타임 출력 및 에러 실시간 로그 기록 장부 가동
exec > >(tee -a /var/log/apps/aidas-test.log) 2>&1

echo "=== [1/5] 기본 패키지 및 런타임 엔진(Docker, Nginx) 설치 ==="
dnf remove -y podman buildah cgroupby
dnf update -y
dnf install -y docker jq nginx stress

# Docker Compose V2 코어 플러그인 설치
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.26.0/docker-compose-linux-x86_64 -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

rm -f /etc/nginx/conf.d/default.conf
curl -o /etc/nginx/conf.d/nginx.conf \
  https://raw.githubusercontent.com/KT-TECHUP-AIDAS/aidas/master/infra/nginx/nginx.conf

systemctl enable --now nginx
systemctl enable --now docker
usermod -aG docker ec2-user

echo "=== [2/5] 디렉토리 생성 및 권한 부여 ==="
# 1) promtail_base_dir & promtail_config_dir 생성 (mode: 0755)
mkdir -p /opt/promtail
mkdir -p /opt/promtail/config
chmod 755 /opt/promtail
chmod 755 /opt/promtail/config

# 2) promtail_positions_dir 생성 (컨테이너 쓰기 차단 방지 mode: 0777)
mkdir -p /var/lib/promtail
chmod 777 /var/lib/promtail


echo "=== [3/5] promtail-config.yaml 배포 (정규식/Drop 포함) ==="
cat << 'PROMTAIL_CONF' > /opt/promtail/config/promtail-config.yaml
server:
  http_listen_port: 9080
  grpc_listen_port: 0

positions:
  filename: /var/lib/promtail/positions.yaml

clients:
  - url: http://172.16.8.201:3100/loki/api/v1/push  # rocky01 private ip

scrape_configs:
  - job_name: system-logs
    static_configs:
      - targets:
          - localhost
        labels:
          job: system-logs
          host: aws-asg-ec2
          service_name: nginx-web
          component: web-tier
          __path__: /var/log/apps/*.log

    pipeline_stages:
      - regex:
          expression: '^(?P<level>WARNING|WARN|ERROR|FATAL|CRITICAL|INFO|DEBUG):\s*\[(?P<component>[^\]]+)\]\s*(?P<message>.*)'

      - labels:
          level:
          component:

#      - match:
#          selector: '{level!~"WARNING|WARN|ERROR|FATAL|CRITICAL"}'
#          action: drop
PROMTAIL_CONF

# 플레이스홀더 인스턴스 고유 호스트네임으로 라이브 치환
sed -i "s/aws-asg-ec2/$(hostname)/g" /opt/promtail/config/promtail-config.yaml

echo "=== [4/5] docker-compose-promtail.yml 배포 ==="
cat << 'COMPOSE_CONF' > /opt/promtail/docker-compose-promtail.yml
version: "3.9"

services:
  promtail:
    image: grafana/promtail:3.0.0
    container_name: promtail
    restart: unless-stopped
    command: -config.file=/etc/promtail/promtail-config.yaml
    volumes:
      # 호스트의 /opt/promtail/config/ 설정을 컨테이너의 기본 컨텍스트 주소로 마운트
      - /opt/promtail/config/promtail-config.yaml:/etc/promtail/promtail-config.yaml:ro
      - /var/log/apps:/var/log/apps:ro
      - /var/lib/promtail:/var/lib/promtail
COMPOSE_CONF

echo "=== [5/5] Promtail Agent 컨테이너 기동 ==="
cd /opt/promtail
docker compose -f docker-compose-promtail.yml up -d

echo "=== AWS 온디맨드 에이전트 파이프라인 아키텍처 동기화 완료 ==="
EOF
  )

  tag_specifications {
    resource_type = "instance"
    tags          = { Name = "asg-instance" }
  }
}



# 4. ─── Blue ASG ─────────────────────────────────────────────────────
resource "aws_autoscaling_group" "asg_blue" {
  name                = "${var.project_name}-asg-blue"
  vpc_zone_identifier = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  max_size            = var.max_size
  min_size            = 0
  desired_capacity    = 2
  depends_on = [
  aws_instance.nat_ec2_a,
  aws_instance.nat_ec2_c
]
  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  default_cooldown          = 60
  target_group_arns         = [aws_lb_target_group.blue_tg.arn]  # Blue TG
  health_check_type         = "ELB"
  health_check_grace_period = 300

  tag {
    key                 = "Name"
    value               = "${var.project_name}-blue"
    propagate_at_launch = true
  }
}

# 5. ─── Green ASG ────────────────────────────────────────────────────
resource "aws_autoscaling_group" "asg_green" {
  name                = "${var.project_name}-asg-green"
  vpc_zone_identifier = [aws_subnet.private_subnet_1.id, aws_subnet.private_subnet_2.id]
  max_size            = 4
  min_size            = 0             # 평소엔 0 (비용 절감)
  desired_capacity    = 0             # 배포 시에만 올림

  launch_template {
    id      = aws_launch_template.lt.id
    version = "$Latest"
  }

  default_cooldown          = 60
  target_group_arns         = [aws_lb_target_group.green_tg.arn]  # Green TG
  health_check_type         = "ELB"
  health_check_grace_period = 120

  tag {
    key                 = "Name"
    value               = "${var.project_name}-green"
    propagate_at_launch = true
  }
}





# 6. 동적 스케일링 정책
# ─── 스케일링 정책 (Blue) ─────────────────────────────────────────
resource "aws_autoscaling_policy" "cpu_scaling_blue" {
  name                   = "${var.project_name}-cpu-blue"
  autoscaling_group_name = aws_autoscaling_group.asg_blue.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

# ─── 스케일링 정책 (Green) ────────────────────────────────────────
resource "aws_autoscaling_policy" "cpu_scaling_green" {
  name                   = "${var.project_name}-cpu-green"
  autoscaling_group_name = aws_autoscaling_group.asg_green.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 50.0
  }
}

# 7. ASG에 의해 생성된 EC2 인스턴스 출력
# Blue 인스턴스 조회
data "aws_instances" "blue_nodes" {
  depends_on = [aws_autoscaling_group.asg_blue]
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.asg_blue.name
  }
  instance_state_names = ["running"]
}

# Green 인스턴스 조회
data "aws_instances" "green_nodes" {
  depends_on = [aws_autoscaling_group.asg_green]
  instance_tags = {
    "aws:autoscaling:groupName" = aws_autoscaling_group.asg_green.name
  }
  instance_state_names = ["running"]
}

