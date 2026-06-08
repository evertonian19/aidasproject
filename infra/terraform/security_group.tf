# security_group.tf
# ├── alb_sg -80, 443 포트 허용
# ├── ssh_sg -온프레미스 통신 전용
# └── ec2_sg -22, tailscale 대역만 허용
# └── asg_sg -22 (tailscale), 80(ALB) 포트 허용

#  ALB 전용 보안 그룹 (Security Group)
resource "aws_security_group" "alb_sg" {
  name        = "${var.project_name}-alb-sg"
  description = "Allow HTTP and HTTPS traffic"
  vpc_id      = aws_vpc.main.id #

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-alb-sg" }
}

# 온프레미스와 통신을 위한 전용 보안그룹
resource "aws_security_group" "ec2_sg" {
  vpc_id = aws_vpc.main.id
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.onpremise_cidr] # 온프레미스 네트워크 CIDR로 제한
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.project_name}-ec2-sg" }
}

resource "aws_security_group" "ssh_sg" {
  name        = "${var.project_name}-ssh-sg"
  description = "Allow SSH access only via Tailscale network" # 테일스케일 네트워크에서만 SSH 접근 허용
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from Tailscale only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]  # Tailscale IP 대역
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ssh-sg" }
}
# ASG(웹서버) 전용 보안 그룹
resource "aws_security_group" "asg_sg" {
  name   = "${var.project_name}-asg-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]          # Tailscale만
  }
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]  # ALB만
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-asg-sg" }
}