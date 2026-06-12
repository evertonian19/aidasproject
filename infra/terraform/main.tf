# [Terraform 메인]  EC2, Lambda 등 프로젝트에 필요한 핵심 AWS 인프라 리소스들을 선언하고 조율하는 파일입니다.

# main.tf
# ├── EC2 인스턴스
# ├── Tailscale 연동
# ├── Ansible 실행


resource "aws_instance" "my_ec2" {
    ami                     = data.aws_ami.latest_al2023.id 
    instance_type           = var.instance_type 
    key_name                = aws_key_pair.kp.key_name  
    iam_instance_profile = aws_iam_instance_profile.ec2_profile.name
    # subnet은 ENI와 같은 서브넷으로 지정
    subnet_id              = aws_subnet.private_subnet_1.id
    vpc_security_group_ids = [aws_security_group.ssh_sg.id, aws_security_group.ec2_sg.id]
        
    user_data = base64encode(<<-EOF
        #!/bin/bash
        # 로그 파일 생성 및 모든 출력 기록
        exec > >(tee -a /var/log/user_data_final.log) 2>&1

        # 1. 호스트네임 및 시스템 기본 설정
        hostnamectl set-hostname "${var.host_name}"
        echo "127.0.0.1 ${var.host_name}" >> /etc/hosts
        

        # 2. 인터넷 대기 (Private Subnet이므로 NAT 준비 대기)
        echo "인터넷 연결 대기 중..."
        for i in $(seq 1 60); do
            if ping -c 1 8.8.8.8 &> /dev/null; then
            echo "인터넷 연결 성공! ($i번째 시도)"
            break
            fi
            echo "대기 중... ($i/60)"
            sleep 5
        done
        # 3-1. 패키지설치
        dnf install -y jq

        # 3-2. Tailscale 설치 및 IP 포워딩 활성화
        curl -fsSL https://tailscale.com/install.sh | sh
        systemctl enable --now tailscaled
        
        # 4. IP Forwarding 활성화
        cat <<EOT > /etc/sysctl.d/99-tailscale.conf
        net.ipv4.ip_forward = 1
        net.ipv6.conf.all.forwarding = 1
        EOT
        sysctl -p /etc/sysctl.d/99-tailscale.conf

        # 5. Tailscale 가입 (생성된 Auth Key 사용)
        # --advertise-routes만 던져두면, 승인은 테라폼이 밖에서 해줍니다.
        tailscale up --authkey=${tailscale_tailnet_key.ec2_join_key.key} \
                     --advertise-routes=${aws_vpc.main.cidr_block} \
                     --accept-routes
        cat <<'EOT' > /home/ec2-user/aidas-key.pem
        ${tls_private_key.pk.private_key_pem}
        EOT
        chmod 600 /home/ec2-user/aidas-key.pem
        chown ec2-user:ec2-user /home/ec2-user/aidas-key.pem
    EOF
    )   
    tags = {
        Name = "aidas-ec2"
    }
}

# 테라폼이 기기를 찾고 라우팅을 승인하는 부분
data "tailscale_device" "my_ec2_device" {
  # db-server 호스트를 tailscale에서 승인하도록 체크
  hostname   = var.host_name
  wait_for   = "180s" # 기기가 리스트에 뜰 때까지 테라폼이 기다려줍니다.
  depends_on = [aws_instance.my_ec2]
}

resource "tailscale_device_subnet_routes" "approve_vpc_routes" {
  device_id = data.tailscale_device.my_ec2_device.id
  routes    = [aws_vpc.main.cidr_block]
}



resource "local_file" "ansible_inventory"{
    filename = "${path.module}/inventory.yml"
    content = yamlencode({
        all = {
            hosts = {
                # [수정] 인벤토리에 EC2의 Tailscale IP 사용
                "${data.tailscale_device.my_ec2_device.addresses[0]}" = {
                    ansible_user = "ec2-user"
                    ansible_ssh_private_key_file = "${path.module}/aidas-key.pem"
                }
            }
        }
    })
}

resource "local_file" "ansible_config"{
    filename = "${path.module}/ansible.cfg"
    content = <<-EOF
        [defaults]
        inventory = ./inventory.yml
        host_key_checking = False
    EOF
}

resource "terraform_data" "wait_for_instance"{
    depends_on = [aws_instance.my_ec2, local_file.ansible_inventory, local_file.ansible_config]
    triggers_replace = aws_instance.my_ec2.id

    provisioner "local-exec" {
        # user_data에서 Tailscale 세팅이 완벽히 끝날 때까지 넉넉하게 대기 (2분 30초)
        #  Tailscale 경로가 갱신되어야 Ansible이 Tailscale IP로 접근 가능합니다.
        command = <<-EOT
            until tailscale status --json | jq -e \
                '.Peer[] | select(.HostName == "${var.host_name}")' > /dev/null 2>&1; do
                echo "Tailscale peer 대기중..."
                sleep 10
            done
            echo "Tailscale peer 연결 확인 완료!"
            EOT
    }
}

#resource "terraform_data" "ansible_run"{
    #depends_on = [ terraform_data.wait_for_instance ]
    #triggers_replace = {
    #    instance_id = aws_instance.my_ec2.id
        
   # }
   # provisioner "local-exec" {
   #    command = "ANSIBLE_SSH_PIPELINING=1 ansible-playbook site.yml"
   #    environment = {
   #      DOCKERHUB_USERNAME = var.dockerhub_username
   #      DOCKERHUB_TOKEN    = var.dockerhub_token
  #       DB_URL             = var.db_url
 #      }
#    }
