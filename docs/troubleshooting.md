# 🔧 AIDAS Troubleshooting DB

> 프로젝트 진행 중 발생한 실제 장애 및 이슈 기록  
> 장애 발견 → 원인 분석 → 해결 → 재발 방지 순서로 정리

---

## 목차

1. [NAT EC2 — ECS 최적화 AMI 선택으로 인터넷 연결 불가](#1-nat-ec2--ecs-최적화-ami-선택으로-인터넷-연결-불가)
2. [ASG desired_capacity — TargetTracking 정책 충돌](#2-asg-desired_capacity--targettracking-정책-충돌)
3. [Blue/Green CD 파이프라인 — Listener 전환 버그](#3-bluegreen-cd-파이프라인--listener-전환-버그)
4. [Loki 폴링 — handler.py KST 타임스탬프 이슈](#4-loki-폴링--handlerpy-kst-타임스탬프-이슈)

---

## 1. NAT EC2 — ECS 최적화 AMI 선택으로 인터넷 연결 불가

**발생 위치**: `infra/terraform/modules/ec2/main.tf`  
**심각도**: 🔴 Critical — Private Subnet EC2 전체 인터넷 연결 불가

### 문제 상황

```
Private Subnet의 Blue/Green EC2에서 외부 인터넷 접근 불가
curl https://google.com → 타임아웃
Docker 이미지 pull → 실패
```

### 원인 분석

Terraform AMI 필터에 와일드카드를 사용했는데, 해당 필터가 일반 Amazon Linux 2023이 아닌 **ECS 최적화 AMI**를 선택하는 문제 발생.

```hcl
# 문제가 된 필터
data "aws_ami" "nat" {
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]  # ← ECS 최적화 AMI도 매칭됨
  }
}
```

ECS 최적화 AMI는 Docker가 사전 설치되어 있고, 보안 정책상 **iptables FORWARD 정책이 기본 DROP**으로 설정되어 있음.

```bash
# ECS 최적화 AMI에서 확인된 상태
$ iptables -L FORWARD
Chain FORWARD (policy DROP)  # ← NAT 동작 불가 원인
```

NAT EC2가 패킷을 포워딩해야 하는데 FORWARD 정책이 DROP이라 모든 패킷이 차단됨.

### 해결 방법

**① AMI 필터를 더 구체적으로 지정**

```hcl
data "aws_ami" "nat" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]  # ECS 제외, 일반 AL2023만
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}
```

**② user_data에 FORWARD 정책 명시적 허용 추가**

```bash
#!/bin/bash
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p

# iptables FORWARD 정책 명시적 허용 (ECS AMI 대비 안전장치)
iptables -P FORWARD ACCEPT
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```

### 재발 방지

- AMI 필터 와일드카드 사용 시 반드시 `aws ec2 describe-images`로 선택될 AMI 사전 검증
- NAT EC2 user_data에 `iptables -P FORWARD ACCEPT` 항상 명시적으로 포함
- Terraform plan 단계에서 선택된 AMI ID 출력하여 확인

```hcl
output "nat_ami_id" {
  value = data.aws_ami.nat.id  # plan 시 AMI ID 확인용
}
```

---

## 2. ASG desired_capacity — TargetTracking 정책 충돌

**발생 위치**: `infra/terraform/modules/asg/main.tf`  
**심각도**: 🟠 High — Terraform apply 시 ASG 상태 불일치

### 문제 상황

```
Terraform apply 완료 후 ASG desired_capacity가
코드에 설정한 값과 다르게 변경됨

설정값: desired_capacity = 2
실제값: desired_capacity = 1 or 3 (TargetTracking이 변경)

→ 다음 terraform apply 시 항상 변경사항 감지됨
→ 의도치 않은 인스턴스 수 변경 발생
```

### 원인 분석

TargetTracking 스케일링 정책이 실시간으로 `desired_capacity`를 조정하는데, Terraform은 코드에 명시된 값과 다르다고 판단하여 매번 덮어씌우려 함.

```hcl
# 충돌 발생 코드
resource "aws_autoscaling_group" "app" {
  desired_capacity = 2  # ← Terraform이 관리
  min_size         = 1
  max_size         = 4
  # TargetTracking 정책도 동시에 desired_capacity 조정 → 충돌
}
```

### 해결 방법

`lifecycle` 블록으로 `desired_capacity`를 Terraform 관리 대상에서 제외.

```hcl
resource "aws_autoscaling_group" "app" {
  desired_capacity = 2
  min_size         = 1
  max_size         = 4

  lifecycle {
    ignore_changes = [desired_capacity]  # ← 추가
  }
}
```

### 재발 방지

- ASG + Auto Scaling 정책 함께 사용 시 `ignore_changes = [desired_capacity]` 기본 패턴으로 적용
- 초기 배포 시에만 `desired_capacity` 적용하고 이후는 스케일링 정책에 위임

---

## 3. Blue/Green CD 파이프라인 — Listener 전환 버그

**발생 위치**: `.github/workflows/deploy.yml`  
**심각도**: 🟠 High — Blue/Green 전환 시 엉뚱한 Target Group으로 트래픽 전송

### 문제 상황

```
Blue → Green 배포 시 ALB Listener가
의도한 Target Group이 아닌 반대 Target Group으로 전환됨

Blue 배포 중인데 Green으로 트래픽 감
→ 배포 안 된 구버전으로 트래픽 전송
→ 서비스 중단
```

### 원인 분석

GitHub Actions에서 Listener 전환 시 **배열 인덱스([0], [1])** 로 Target Group을 참조했는데, AWS CLI 응답 순서가 보장되지 않아 의도와 다른 Target Group이 선택됨.

```yaml
# 문제가 된 코드
- name: Switch ALB Listener
  run: |
    TG_ARN=$(aws elbv2 describe-target-groups \
      --query 'TargetGroups[0].TargetGroupArn')  # ← 인덱스로 참조 (순서 보장 안됨)

    aws elbv2 modify-listener \
      --listener-arn $LISTENER_ARN \
      --default-actions Type=forward,TargetGroupArn=$TG_ARN
```

### 해결 방법

인덱스 대신 **포트 번호**로 Target Group을 필터링하여 명시적으로 참조.

```yaml
- name: Switch ALB Listener to Green
  run: |
    GREEN_TG_ARN=$(aws elbv2 describe-target-groups \
      --names "aidas-green-tg" \
      --query 'TargetGroups[?Port==`8001`].TargetGroupArn' \
      --output text)

    aws elbv2 modify-listener \
      --listener-arn $LISTENER_ARN \
      --default-actions Type=forward,TargetGroupArn=$GREEN_TG_ARN

    echo "Green TG로 전환 완료: $GREEN_TG_ARN"
```

### 재발 방지

- AWS CLI로 리소스 참조 시 인덱스 대신 Name 태그 또는 포트 번호로 명시적 필터링
- 전환 후 실제 Target Group ARN을 로그로 출력하여 검증
- Blue/Green 전환 전 현재 활성 Target Group 확인 단계 추가

---

## 4. Loki 폴링 — handler.py KST 타임스탬프 이슈

**발생 위치**: `lambda/analyzer/handler.py`  
**심각도**: 🟡 Medium — 장애 로그 감지 누락 또는 중복 감지

### 문제 상황

```
Loki에서 ERROR 로그 폴링 시
일부 로그가 감지되지 않거나 이미 처리한 로그를 중복 처리

Slack 알림이 오지 않거나 동일 알림이 2번 전송됨
```

### 원인 분석

handler.py에서 Loki 쿼리 시간 범위를 UTC 기준으로 계산했는데, 온프레미스 Loki 서버가 **KST(UTC+9)** 로 설정되어 있어 9시간 오차 발생.

```python
# 문제 코드
import datetime

now = datetime.datetime.utcnow()  # ← UTC 기준으로 계산
start = now - datetime.timedelta(minutes=5)

params = {
    "start": start.timestamp(),
    "end": now.timestamp(),
}
# Loki는 KST 기준 → 9시간 차이 → 로그 감지 누락
```

### 해결 방법

**① handler.py KST 명시적 처리**

```python
import datetime
import pytz

KST = pytz.timezone('Asia/Seoul')
now = datetime.datetime.now(KST)
start = now - datetime.timedelta(minutes=5)

params = {
    "start": str(int(start.timestamp() * 1e9)),  # Loki는 나노초
    "end": str(int(now.timestamp() * 1e9)),
}
```

**② 근본 해결 — Loki 서버 타임존 UTC로 통일**

```yaml
# docker-compose.yml
services:
  loki:
    environment:
      - TZ=UTC  # ← 모든 컨테이너 UTC 통일
```

### 재발 방지

- 분산 시스템에서 타임스탬프는 모두 **UTC로 통일**하는 것을 원칙으로
- Loki, Prometheus, FastAPI 컨테이너 전부 `TZ=UTC` 환경변수 설정
- 폴링 로직에 마지막 처리 타임스탬프를 저장하여 중복 처리 방지

---

## 트러블슈팅 패턴 정리

| # | 이슈 | 원인 | 핵심 교훈 |
|---|------|------|-----------|
| 1 | NAT 동작 불가 | ECS AMI 와일드카드 필터 | AMI 선택 시 사전 검증 필수 |
| 2 | ASG 충돌 | Terraform vs 스케일링 정책 | `ignore_changes` 패턴 숙지 |
| 3 | Blue/Green 버그 | 배열 인덱스 참조 | 리소스는 Name/포트로 명시적 참조 |
| 4 | 로그 감지 누락 | UTC/KST 타임존 혼용 | 분산 시스템은 UTC 통일 |
