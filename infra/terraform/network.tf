# network.tf
# ├── VPC
# ├── Subnet
# ├── Route Table
# ├── NAT EC2 (nat_ec2_a, nat_ec2_c)  ← 변경
# └── ENI 


# 2. vpc 및 네트워크 생성 (인프라의 기초 공사)
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  tags = {
    Name = "${var.project_name}-vpc"
  }
}
# 인터넷 게이트 웨이
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.project_name}-igw"
  }
}


# 퍼블릭 서브넷1
resource "aws_subnet" "public_subnet_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr1
  availability_zone       = var.avail_zone_1
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-subnet-1" }
}
# 퍼블릭 서브넷2
resource "aws_subnet" "public_subnet_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr2
  availability_zone       = var.avail_zone_2
  map_public_ip_on_launch = true
  tags                    = { Name = "${var.project_name}-public-subnet-2" }
}

# 프라이빗 서브넷1
resource "aws_subnet" "private_subnet_1"{
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr1
  availability_zone       = var.avail_zone_1
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-private-subnet-1" }
}
# 프라이빗 서브넷2
resource "aws_subnet" "private_subnet_2"{
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidr2
  availability_zone       = var.avail_zone_2
  map_public_ip_on_launch = false
  tags = { Name = "${var.project_name}-private-subnet-2" }
}


# NAT EC2 - AZ-A
resource "aws_instance" "nat_ec2_a" {
  ami                    = data.aws_ami.latest_al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_1.id  # 퍼블릭 서브넷
  vpc_security_group_ids = [aws_security_group.nat_sg.id]
  key_name               = aws_key_pair.kp.key_name
  source_dest_check      = false  # NAT 필수 설정
  associate_public_ip_address = true  # public ip자동할당 ← 추가
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    # IP 포워딩 활성화
    cat <<EOT > /etc/sysctl.d/99-nat.conf
    net.ipv4.ip_forward = 1
    EOT
    sysctl -p /etc/sysctl.d/99-nat.conf

    # NAT iptables 설정
    dnf install -y iptables-services
    PRIMARY_IF=$(ip route show default | awk '/default/ {print $5}' | head -1)
    iptables -t nat -A POSTROUTING -o $PRIMARY_IF -j MASQUERADE
    iptables-save > /etc/sysconfig/iptables
    systemctl enable --now iptables
  EOF
  )

  tags = { Name = "${var.project_name}-nat-ec2-a" }
}

# NAT EC2 - AZ-C
resource "aws_instance" "nat_ec2_c" {
  ami                    = data.aws_ami.latest_al2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public_subnet_2.id  # 퍼블릭 서브넷
  vpc_security_group_ids = [aws_security_group.nat_sg.id]
  key_name               = aws_key_pair.kp.key_name
  source_dest_check      = false  # NAT 필수 설정
  associate_public_ip_address = true
  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    cat <<EOT > /etc/sysctl.d/99-nat.conf
    net.ipv4.ip_forward = 1
    EOT
    sysctl -p /etc/sysctl.d/99-nat.conf

    dnf install -y iptables-services
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
    iptables-save > /etc/sysconfig/iptables
    systemctl enable --now iptables
  EOF
  )

  tags = { Name = "${var.project_name}-nat-ec2-c" }
}

# NAT EC2용 EIP
resource "aws_eip" "nat_ec2_a_eip" {
  instance   = aws_instance.nat_ec2_a.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-ec2-a-eip" }
}

resource "aws_eip" "nat_ec2_c_eip" {
  instance   = aws_instance.nat_ec2_c.id
  domain     = "vpc"
  depends_on = [aws_internet_gateway.igw]
  tags       = { Name = "${var.project_name}-nat-ec2-c-eip" }
}

##---------퍼블릭 라우팅 테이블
resource "aws_route_table" "public_rt" {
  # vpc 연결
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    # 인터넷 게이트웨이 연결
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

# 라우팅 테이블과 퍼블릭 서브넷_1 연결
resource "aws_route_table_association" "public_assoc_1" {
  subnet_id      = aws_subnet.public_subnet_1.id
  route_table_id = aws_route_table.public_rt.id
}
# 라우팅 테이블과 퍼블릭 서브넷_2 연결
resource "aws_route_table_association" "public_assoc_2" {
  subnet_id      = aws_subnet.public_subnet_2.id
  route_table_id = aws_route_table.public_rt.id
}


#-----------------프라이빗 라우팅 테이블
resource "aws_route_table" "private_rt_a" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt-a" }
}

resource "aws_route_table" "private_rt_c" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project_name}-private-rt-c" }
}


# ── Private Route Table NAT 경로 → NAT EC2로 변경 ──────────────
resource "aws_route" "private_nat_route_a" {
  depends_on             = [aws_instance.nat_ec2_a] # Private Route가 NAT EC2보다 먼저 생성되지 않도록 설정.
  route_table_id         = aws_route_table.private_rt_a.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat_ec2_a.primary_network_interface_id
}

resource "aws_route" "private_nat_route_c" {
  depends_on             = [aws_instance.nat_ec2_c]
  route_table_id         = aws_route_table.private_rt_c.id
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = aws_instance.nat_ec2_c.primary_network_interface_id
}


# 라우팅 테이블과 프라이빗 서브넷_1 연결
resource "aws_route_table_association" "private_assoc_1" {
  subnet_id      = aws_subnet.private_subnet_1.id
  route_table_id = aws_route_table.private_rt_a.id
}
# 라우팅 테이블과 프라이빗 서브넷_2 연결
resource "aws_route_table_association" "private_assoc_2" {
  subnet_id      = aws_subnet.private_subnet_2.id
  route_table_id = aws_route_table.private_rt_c.id
}

# Tailscale 인증키 자동 발급
resource "tailscale_tailnet_key" "ec2_join_key" {
    reusable = true
    ephemeral = false
    preauthorized = true # 자동연결
    expiry = 2592000 # 30일
}

# Tailscale 온프레미스 연동 라우팅 (Public & Private 모두 적용)
# ----------------------------------------------------
# Public Subnet에서 172.16.8.0/24로 갈 때 EC2를 거치도록 설정

# ENI를 EC2보다 먼저 독립적으로 생성
# ─── 1. ENI 먼저 독립 생성 ───────────────────────────────────────
resource "aws_network_interface" "tailscale_eni" {
  subnet_id         = aws_subnet.private_subnet_1.id
  source_dest_check = false  # 라우터 역할 필수!
  security_groups = [
    aws_security_group.ssh_sg.id,
    aws_security_group.ec2_sg.id
    ]
  tags = {
    Name = "${var.project_name}-tailscale-eni"
  }
}
# 수정 코드 (ENI 직접 참조 - 순환 없음)
resource "aws_route" "to_onpremise_public" {
  route_table_id         = aws_route_table.public_rt.id
  destination_cidr_block = var.onpremise_cidr   # 변수로도 분리
  network_interface_id   = aws_network_interface.tailscale_eni.id
}

resource "aws_route" "to_onpremise_private_a" {
  route_table_id         = aws_route_table.private_rt_a.id
  destination_cidr_block = var.onpremise_cidr
  network_interface_id   = aws_network_interface.tailscale_eni.id  # ✅
}

resource "aws_route" "to_onpremise_private_c" {
  route_table_id         = aws_route_table.private_rt_c.id
  destination_cidr_block = var.onpremise_cidr
  network_interface_id   = aws_network_interface.tailscale_eni.id  # ✅
}