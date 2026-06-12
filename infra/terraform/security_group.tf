# security_group.tf
# ├── nat_sg - NAT EC2용 보안 그룹 <- 추가 
# ├── alb_sg -80, 443 포트 허용
# ├── ec2_sg  - 온프레미스 통신 전용 (172.16.8.0/24)
# ├── ssh_sg  - SSH, Tailscale 대역만 허용 (100.64.0.0/10)
# └── asg_sg -22 (tailscale), 80(ALB) 포트 허용

# NAT EC2용 보안 그룹
resource "aws_security_group" "nat_sg" {
  name   = "${var.project_name}-nat-sg"
  vpc_id = aws_vpc.main.id
  ingress {
  description = "SSH from Tailscale only"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # Tailscale 대역변경 전체허용
  }
  # Private Subnet에서 오는 모든 트래픽 허용
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-nat-sg" }
}


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
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.vpc_cidr]  # VPC 내부 접근 허용
  }
  ingress {
    description = "SSH from Tailscale only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["100.64.0.0/10"]  # Tailscale IP 대역
  }
  ingress {
    description = "ICMP from VPC (for health/troubleshooting)"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  ingress {
    description = "Loki HTTP from VPC"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
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
    cidr_blocks = ["10.0.0.0/16"]          # Tailscale만
  }
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
      ingress {
    description = "ICMP from onpremise"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-asg-sg" }
}