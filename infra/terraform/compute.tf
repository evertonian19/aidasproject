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

locals {
  promtail_config = templatefile("${path.module}/templates/promtail-config.yaml.tftpl", {
    loki_url = var.loki_url
  })

  promtail_compose = templatefile("${path.module}/templates/docker-compose-promtail.yml.tftpl", {})
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
  user_data = base64encode(
    templatefile("${path.module}/templates/cloud-init-promtail.tftpl", {
      promtail_config_b64  = base64encode(local.promtail_config)
      promtail_compose_b64 = base64encode(local.promtail_compose)
    })
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

