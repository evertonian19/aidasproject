# AIDAS 전체 시스템 테스트 가이드

**환경:** AWS (EC2/ALB/Lambda) + On-Premise VMware (rocky01/rocky02)  
**흐름:** 장애 주입 → Promtail → Loki → handler.py → Ollama → Lambda → Slack

---

## 0. 사전 준비

### 필수 도구 설치 (mgmt / 172.16.8.200, Rocky Linux)

```bash
# Terraform
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/RHEL/hashicorp.repo
sudo dnf install -y terraform

# AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o awscliv2.zip
unzip awscliv2.zip && sudo ./aws/install
aws configure --profile aidasProject2

# Ansible
pip3 install ansible

# Tailscale (mgmt도 같은 테일넷에 가입)
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=<tailscale_auth_key>

# SSH 키 생성 (Ansible용)
ssh-keygen -t rsa -b 4096 -f ~/.ssh/aidas_onprem.pem -N ""
ssh-copy-id -i ~/.ssh/aidas_onprem.pem.pub user1@172.16.8.201
ssh-copy-id -i ~/.ssh/aidas_onprem.pem.pub user1@172.16.8.202
```

### terraform.tfvars 값 확인

```bash
cat /home/user1/project/infra/terraform/terraform.tfvars
# db_url의 호스트를 rocky01 Tailscale IP로 교체 필요
# postgresql://aidas_user:aidas_password@<rocky01_tailscale_ip>:5432/aidas_db
```

---

## 1. Tailscale VPN (rocky01 / rocky02)

```bash
# Rocky Linux 9
curl -fsSL https://pkgs.tailscale.com/stable/rhel/9/tailscale.repo \
  | sudo tee /etc/yum.repos.d/tailscale.repo
sudo dnf install -y tailscale
sudo systemctl enable --now tailscaled
sudo tailscale up --authkey=<tailscale_auth_key>

# 연결 확인 및 Tailscale IP 메모
tailscale ip -4

# 방화벽 허용
sudo firewall-cmd --permanent --zone=trusted --add-interface=tailscale0
sudo firewall-cmd --permanent --add-port=3100/tcp  # Loki
sudo firewall-cmd --permanent --add-port=3000/tcp  # Grafana
sudo firewall-cmd --permanent --add-port=9090/tcp  # Prometheus
sudo firewall-cmd --permanent --add-port=11434/tcp # Ollama
sudo firewall-cmd --permanent --add-port=5432/tcp  # PostgreSQL
sudo firewall-cmd --reload
```

---

## 2. AWS 인프라 프로비저닝 (Terraform)

```bash
cd /home/user1/project/infra/terraform

terraform init
terraform plan
terraform apply -auto-approve
```

**apply 후 자동으로 처리되는 것:**
- VPC / Subnet / ALB / Blue·Green ASG / EC2 (Tailscale 자동 가입)
- Lambda (`aidas-slack-alert`) / DynamoDB (`aidas-incidents`)
- GitHub Secrets 8개 자동 등록 (EC2_HOST, EC2_SSH_KEY, DOCKERHUB_\*, DB_URL, AWS_\*)

```bash
# 결과 확인
terraform output
gh secret list --repo KT-TECHUP-AIDAS/aidas
```

> `provider.tf`의 GitHub provider 주석이 해제되어 있어야 Secrets가 등록됩니다.

---

## 3. On-Premise 자동화 (Ansible)

```bash
cd /home/user1/project/deploy/onprem/ansible

# 연결 확인
ansible all -m ping

# 전체 스택 배포 (Docker + PLG + Prometheus + Promtail + NodeExporter + handler.py)
export GRAFANA_ADMIN_PASSWORD="admin1234"
ansible-playbook playbooks/site.yml -v
```

---

## 4. Docker + Ollama 수동 확인 (rocky01)

```bash
# Docker 설치 확인
docker ps

# Ollama 설치 (Ansible에 포함 안 된 경우)
curl -fsSL https://ollama.com/install.sh | sh
sudo systemctl enable --now ollama

# 모델 Pull (약 4.7GB, 10~30분 소요)
ollama pull qwen2.5-coder:7b
ollama list  # 설치 확인

# handler.py 환경변수 파일 생성
cat > /home/user1/aidas/.env << 'EOF'
LOKI_URL=http://localhost:3100
OLLAMA_API_URL=http://localhost:11434/api/generate
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY
AWS_REGION=ap-northeast-2
LAMBDA_FUNCTION_NAME=aidas-slack-alert
PROMPT_PATH=/home/user1/aidas/prompts/system_prompt.txt
EOF
chmod 600 /home/user1/aidas/.env

# handler.py 실행 확인
tail -f /home/user1/aidas/handler.log
```

---

## 5. DB Node 1 — PostgreSQL Primary (rocky01)

```bash
# 설치
sudo dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
sudo dnf -qy module disable postgresql
sudo dnf install -y postgresql15-server postgresql15
sudo /usr/pgsql-15/bin/postgresql-15-setup initdb
sudo systemctl enable --now postgresql-15

# 계정 및 DB 생성
sudo -u postgres psql << 'EOF'
CREATE USER aidas_user WITH PASSWORD 'aidas_password';
CREATE DATABASE aidas_db OWNER aidas_user;
GRANT ALL PRIVILEGES ON DATABASE aidas_db TO aidas_user;
EOF

# 시드 데이터
sudo -u postgres psql -d aidas_db -f /home/user1/project/init.sql

# 외부 접속 허용
sudo sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" \
  /var/lib/pgsql/15/data/postgresql.conf

sudo tee -a /var/lib/pgsql/15/data/pg_hba.conf << 'EOF'
host    aidas_db    aidas_user    100.64.0.0/10    md5
host    aidas_db    aidas_user    10.0.0.0/16      md5
host    aidas_db    aidas_user    172.16.8.0/24    md5
EOF

sudo systemctl restart postgresql-15

# 연결 확인
psql -U aidas_user -d aidas_db -h localhost -c "SELECT COUNT(*) FROM products;"
```

---

## 6. DB Node 2 — PostgreSQL Replica (rocky02)

```bash
# ─── Primary (rocky01)에서 실행 ───────────────────────────────────
sudo -u postgres psql -c "CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'repl_password';"

sudo tee -a /var/lib/pgsql/15/data/pg_hba.conf << 'EOF'
host    replication    replicator    172.16.8.202/32    md5
EOF

sudo tee -a /var/lib/pgsql/15/data/postgresql.conf << 'EOF'
wal_level = replica
max_wal_senders = 5
EOF
sudo systemctl restart postgresql-15

# ─── Replica (rocky02)에서 실행 ──────────────────────────────────
# (먼저 PostgreSQL 15 설치 — Primary와 동일한 명령 사용)
sudo -u postgres pg_basebackup \
  -h 172.16.8.201 -U replicator \
  -D /var/lib/pgsql/15/data -P -Xs -R
sudo systemctl enable --now postgresql-15

# 복제 상태 확인 (Primary에서)
sudo -u postgres psql -c "SELECT * FROM pg_stat_replication;"
```

---

## 7. FastAPI 로컬 테스트 (Docker Compose)

```bash
cd /home/user1/project

# Docker Hub 로그인
read -s TOKEN && echo $TOKEN | docker login -u leechangwon --password-stdin

# 빌드 및 실행
docker compose up --build -d
docker compose ps

# 동작 확인
curl http://localhost:8000/api/v1/products

# 브라우저
# http://localhost:8000/user   → 쇼핑몰
# http://localhost:8000/admin  → 장애 제어판
```

---

## 8. CI/CD 배포 테스트

```bash
# deploy.yml 브랜치 활성화
# branches: [] → branches: [master]

cd /home/user1/project
git add .github/workflows/deploy.yml
git commit -m "chore: enable CD trigger"
git push origin master

# GitHub Actions 진행 확인
# Actions → CD → Job 순서:
# 1. build-push  → Docker Hub 이미지 푸시
# 2. deploy-green → EC2 SSH 접속, docker run
# 3. switch-listener → ALB Blue→Green 전환
# 4. rollback (switch-listener 실패 시만)

# EC2 배포 확인
ssh -i aidas-key.pem ec2-user@aidas-server.tail3b2a53.ts.net
docker ps && curl http://localhost:8000/api/v1/products
```

---

## 9. E2E 통합 테스트 — 장애 주입

> EC2 또는 `localhost:8000` 기준

```bash
BASE=http://localhost:8000/api/v1/incident

# 1. DB Timeout
curl -X POST $BASE/db-timeout

# 2. OOM
curl -X POST $BASE/oom

# 3. AZ Failure
curl -X POST $BASE/az-failure

# 4. HTTP 500
curl -X POST $BASE/http500
```

**각 시나리오 후 확인 포인트:**

```bash
# Loki 수신 확인 (15초 내)
curl -G http://172.16.8.201:3100/loki/api/v1/query \
  --data-urlencode 'query={job=~".+"} |~ "ERROR"' \
  --data-urlencode 'limit=3'

# handler.py 로그 (Ollama 분석 시작)
tail -20 /home/user1/aidas/handler.log

# DynamoDB 이력 확인
aws dynamodb scan --table-name aidas-incidents \
  --region ap-northeast-2 --profile aidasProject2 \
  --query "Items[0:3]"

# Grafana: http://172.16.8.201:3000 (admin / admin1234)
# Slack 채널 알림 수신 확인
```

---

## 체크리스트

```
사전 준비
[ ] aws configure --profile aidasProject2
[ ] Tailscale 가입 (mgmt, rocky01, rocky02)
[ ] SSH 키 등록 (rocky01, rocky02)

AWS
[ ] terraform apply 완료
[ ] GitHub Secrets 8개 등록 확인
[ ] Lambda aidas-slack-alert 확인

On-Premise
[ ] Docker 설치 (rocky01, rocky02)
[ ] Ollama + qwen2.5-coder:7b 설치
[ ] Loki / Grafana / Prometheus 기동
[ ] Promtail 기동 (양 노드)
[ ] handler.py 실행 + .env 설정

DB
[ ] PostgreSQL Primary 기동 + 시드 데이터
[ ] pg_hba.conf Tailscale 대역 허용
[ ] Replica 복제 상태 확인

테스트
[ ] docker compose up → /api/v1/products 응답
[ ] CI/CD push → EC2 배포 성공
[ ] 장애 4종 주입 → Slack 알림 수신
[ ] DynamoDB 이력 저장 확인
```

---

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| `GET repos//aidas 404` | provider.tf GitHub provider 주석 처리 | `provider "github" {}` 주석 해제 |
| Docker Hub 401 | 로그인 안 됨 | `echo $TOKEN \| docker login -u leechangwon --password-stdin` |
| Loki 폴링 실패 | Loki 미기동 | `curl http://localhost:3100/ready` |
| Ollama 무응답 | 모델 미설치 | `ollama pull qwen2.5-coder:7b` |
| ALB 헬스체크 실패 | `/health` 엔드포인트 없음 | 작업3 담당자에게 추가 요청 |
| Lambda 호출 실패 | IAM 권한 부족 | `lambda:InvokeFunction` 정책 확인 |
| `aidasProject2 not found` | AWS 프로파일 미설정 | `aws configure --profile aidasProject2` |
| Promtail 미전송 | 수집 경로 없음 | `mkdir -p /var/log/apps` |

---

## 포트 요약

| 서비스 | 호스트 | 포트 |
|--------|--------|------|
| FastAPI | EC2 / localhost | 8000 |
| ALB | AWS | 80 / 443 |
| Loki | rocky01 | 3100 |
| Grafana | rocky01 | 3000 |
| Prometheus | rocky01 | 9090 |
| PostgreSQL | rocky01 | 5432 |
| Ollama | rocky01 | 11434 |
