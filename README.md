
# 🔮🛡️ AIDAS (AI-based Incident Detection and Automated Support)
> AI 기반 장애 로그 자동 탐지 및 알림 운영 시스템
> 클라우드 컨테이너 인프라의 장애 로그를 온프레미스 로컬 AI(Ollama)로 분석하여 원인 요약과 조치 방안을 Slack으로 실시간 전달하는 지능형 관제 시스템
---
## 🛠️ 기술 스택 (Tech Stack)

### Cloud & Infra
![AWS](https://img.shields.io/badge/AWS-%23FF9900.svg?style=flat-square&logo=amazon-aws&logoColor=white)
![VMware](https://img.shields.io/badge/VMware-%2360B91F.svg?style=flat-square&logo=vmware&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-%237B42BC.svg?style=flat-square&logo=terraform&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-%23EE0000.svg?style=flat-square&logo=ansible&logoColor=white)
![Tailscale](https://img.shields.io/badge/Tailscale-%235433FF.svg?style=flat-square&logo=tailscale&logoColor=white)

### Container
![Docker](https://img.shields.io/badge/Docker-%232496ED.svg?style=flat-square&logo=docker&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-%23326CE5.svg?style=flat-square&logo=kubernetes&logoColor=white)

### Observability & AI
![Grafana](https://img.shields.io/badge/Grafana-%23F46800.svg?style=flat-square&logo=grafana&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-%23E6522C.svg?style=flat-square&logo=prometheus&logoColor=white)
![Ollama](https://img.shields.io/badge/Ollama-%23000000.svg?style=flat-square&logo=ollama&logoColor=white)

### Backend & DB
![FastAPI](https://img.shields.io/badge/FastAPI-%23009688.svg?style=flat-square&logo=fastapi&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-%234169E1.svg?style=flat-square&logo=postgresql&logoColor=white)

### CI/CD
![GitHub Actions](https://img.shields.io/badge/GitHub%20Actions-%232088FF.svg?style=flat-square&logo=github-actions&logoColor=white)
---

## 1. 팀 소개 (Team Information)
### 팀명: 쉬지마EC 2
- **이재혁**(팀장): 요구사항 분석, 프로젝트 총괄 및 일정 관리, 온프레미스 환경 내부 로컬 AI 엔진(Ollama) 구축 및 프롬프트 최적화 전담.
- **부학성**(부팀장): 요구사항 분석, 하이브리드 인프라 아키텍처 설계 총괄, 개방형 관제 파이프라인(PLG Stack) 및 AWS CloudWatch 통합 연동 전담.
- **박다정**: 요구사항 분석, Terraform 기반 AWS 클라우드 인프라(VPC, EC2, ALB, Route53, S3, CloudFront) IaC 코드 자동화 및 프로비저닝 담당.
- **이창원:** 요구사항 분석, Ansible Playbook 기반 인프라 배포 자동화, GitHub Actions CI/CD 구축 및 통합 테스트 담당.
- **김민규**: 요구사항 분석, FastAPI 기반 관찰 대상 웹 서비스 및 4대 장애 유발 제어판(Incident Injector) 백엔드/프론트엔드 개발 담당.
---

## 📌 2. 프로젝트 개요 (Executive Summary)
- 배경: 기존 모니터링 도구는 단순 시각화까지만 지원하여 수많은 로그 속에서 원인을 찾고 대응책을 고민하는 일은 결국 운영자의 몫이었습니다. 이는 운영 피로도를 높이고 대응을 지연시키는 문제를 야기합니다.
- 목적: 인프라에서 발생하는 심각한 에러를 실시간 감지하고, 외부 유출과 비용이 없는 온프레미스 로컬 AI(Ollama)가 로그를 1차 분석하여 에러 원인 요약과 맞춤형 대응 가이드를 슬랙으로 즉시 제공하는 관제 시스템 표준화.
- 기대 효과: 로그를 직접 뒤지는 과정을 AI가 대신하여 에러 인지부터 원인 파악까지의 시간(MTTR)을 대폭 감소시킵니다. 외부 API를 쓰지 않고 로컬 인프라 안에서만 LLM을 구동하므로 보안 유출 위험이 원천 차단되며 추가 비용이 없습니다.

---

## 🏗️ 3. 시스템 아키텍처 (System Architecture)
AIDAS는 퍼블릭 클라우드의 탄력성과 온프레미스의 보안 가치를 모두 충족하는 하이브리드 인프라 아키텍처(Hybrid Architecture)를 채택하고 있습니다. 두 환경은 메쉬 VPN(Tailscale)을 통해 암호화된 프라이빗 사설망으로 유기적으로 연동됩니다.

```
[사용자 트래픽] ➔ Route 53 ➔ CloudFront ➔ ALB ➔ EC2 (FastAPI / Promtail)
                                                    │
                                        (Tailscale 보안 터널)
                                                    ▼
                                    VMware On-Premises (Loki / Grafana / Ollama / DB)
                                                    │
                                             (Slack Webhook)
                                                    ▼
                                            [인프라 운영팀]
```

1) AWS 퍼블릭 클라우드 영역 (Frontend & Web Layer)
인프라 라우팅: Amazon Route 53 ➔ Amazon CloudFront ➔ Application Load Balancer (ALB) ➔ Amazon EC2

가동 서비스: FastAPI 웹 애플리케이션, Promtail 에이전트

핵심 역할: 글로벌 엣지(CloudFront) 캐싱을 통해 무거운 정적 리소스를 오프로딩(Offloading)하여 백엔드 부하를 최소화합니다. 애플리케이션에서 발생하는 로그는 Promtail 에이전트를 통해 WARN / ERROR / FATAL 레벨별로 실시간 분류 및 필터링되어 타겟으로 라우팅됩니다.

2) 가상 보안 터널 계층 (Secure Network Layer)
기술 스택: Tailscale 메쉬 VPN

핵심 역할: 퍼블릭 인터넷 노출이 차단된 AWS 프라이빗 서브넷과 온프레미스 데이터센터 간에 점대점(P2P) 암호화 보안 터널을 형성합니다. 이를 통해 외부 유출에 민감한 서버 로그 데이터를 안전하게 내부망으로 전송합니다.

3) VMware 온프레미스 영역 (Data & AI Analytics Layer)
통합 옵저버빌리티(Observability) 센터: Grafana / Prometheus / Loki 기반의 실시간 매트릭·로그 통합 관제 및 시각화 환경을 제공합니다.

로컬 AI 분석 엔진: 사설망 내부에 독립형 LLM 엔진인 Ollama API를 구축하여 기업 자산인 로그 데이터의 외부 유출 리스크를 원천 차단하고, 수집된 스택 트레이스(Stack Trace)의 문맥적 결함을 추론합니다.

메인 데이터베이스: PostgreSQL을 활용하여 시스템 메타데이터 및 장애 이력(Incident History)을 영속적으로 관리합니다.

4) 지능형 알림 전송 (Alerting Layer)
기술 스택: Slack Incoming Webhook

핵심 역할: AI 분석 엔진이 도출한 에러 코드의 정확한 파일명, 발생 라인 수, 조치 권고 사항을 포함한 진단 보고서를 관제 팀 채널로 제로 터치(Zero-Touch) 무인 전송합니다.



## 📂 4. 디렉토리 구조 (Directory Structure)
```text
aidas/
├── .github/              # GitHub Actions Workflows (CI/CD 자동화 파이프라인)
│   └── workflows/
│       ├── ci.yml        # 코드 Push 시 빌드·테스트·Docker 이미지 생성
│       └── deploy.yml    # Docker Hub push 후 Swarm 롤링 업데이트 배포
├── services/
│   └── web/              # FastAPI 피관제 서비스 (구 backend)
│       ├── app/
│       │   ├── routers/  # 상품 API + 4대 장애 유발 제어판 엔드포인트
│       │   ├── templates/# jinja2 (상품 리스트, Incident Injector 화면)
│       │   └── db.py     # PostgreSQL 연결
│       ├── main.py
│       ├── requirements.txt
│       └── Dockerfile
├── lambda/
│   └── analyzer/         # Loki 에러 → Ollama 호출 → Slack 전송 (AWS Lambda)
│       ├── handler.py    # Lambda 진입점
│       ├── ollama_client.py # 온프레미스 Ollama API 호출 (Tailscale 경유)
│       ├── slack_notifier.py # Slack Webhook 메시지 포맷팅·전송
│       └── requirements.txt
├── infra/
│   ├── terraform/        # AWS 리소스 생성 (IaC)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── modules/      # vpc, alb, ec2, route53, cloudfront, lambda 모듈
│   └── ansible/          # 온프레미스 프로비저닝 플레이북
│       ├── playbook.yml  # Docker·Ollama·관제스택 설치 (멱등성)
│       ├── inventory.ini
│       └── roles/        # docker, ollama, monitoring 롤
├── deploy/
│   ├── aws-swarm/        # AWS EC2 클러스터 배포용
│   │   └── swarm-stack.yml # FastAPI + Promtail 컨테이너 설정
│   └── onprem/           # 온프레미스(VMware) 관제·AI 스택
│       ├── docker-compose.yml # Loki + Grafana + Prometheus + PostgreSQL + Ollama
│       └── config/       # 관제 스택 및 프롬테일 설정 파일
├── prompts/              # Ollama 시스템 프롬프트 템플릿 (.txt)
│   ├── system_prompt.txt # SRE 관점 [장애유형/원인/조치] 3단계 출력 규격
│   └── scenarios/        # 4대 장애별 프롬프트 튜닝 버전
└── docs/                 # 산출물 문서
    ├── architecture.md   # 하이브리드 아키텍처 다이어그램
    ├── pipeline-diagram.md # 로그 분석 파이프라인 흐름도
    └── troubleshooting.md # 트러블슈팅 DB (장애 시나리오별 기록)
```

## 🛑 5. 4대 장애 주입 시나리오 (Incident Injector)

1) DB Connection Timeout (🔴 DB 연결 끊김/지연)
- 동작: 제어판 활성화 시 DB 연결 설정을 변조하거나 가짜 IP로 커넥션을 시도하여 타임아웃 유발
- 로그: psycopg2.OperationalError: connection to server at db.local failed: Connection timed out
- AI 가이드: Tailscale VPN 터널 상태 점검 및 DB 방화벽 규칙 확인 권고

2) Out of Memory (🟠 메모리 고갈)
- 동작: 백엔드에서 대규모 메모리를 점유하는 무한 루프 배열 가산 스크립트를 가동하여 OS 자원 임계치 초과 유도
- 로그: kernel: Out of memory: Kill process (python) score or sacrifice child
- AI 가이드: Docker Swarm의 컨테이너 자원 리미트(IaC) 재설정 유도

3) AWS AZ Failure (🟡 가용 영역 장애)
- 동작: 특정 가용 영역(AZ)의 서브넷 네트워크 라우팅을 차단하거나 인스턴스를 강제 종료하여, 단일 데이터센터 수준의 블랙아웃 상황 시뮬레이션
- 로그: 502 Bad Gateway 및 ALB Health Check Failed: target unresponsive in impaired Availability Zone
- AI 가이드: Auto Scaling Group(ASG)의 Multi-AZ 페일오버(Failover) 정상 동작 여부 확인 및 트래픽이 정상 AZ로 안전하게 우회되고 있는지 점검 권고

4) HTTP 500 Error (🔵 애플리케이션 코드 오류)
- 동작: 상품 조회 API 호출 시 의도적으로 Zero Division 또는 Null 참조를 발생시켜 Stack Trace 에러 유도
- 로그: ZeroDivisionError: division by zero 및 Internal Server Error: /api/v1/products
- AI 가이드: Stack Trace 내부 파일명과 라인 수를 요약하고, GitHub Actions 최신 배포 이력 확인 및 소스코드 롤백 제안

---

## 🌿 6. 협업 브랜치 전략 및 PR 규칙 (Git Flow & Pull Request)
- master : 제품으로 출시 및 배포될 수 있는 가장 안정적인 배포 본진 브랜치.
- develop : 다음 버전을 위해 개발을 통합하는 메인 개발 베이스 브랜치.
- feature/기능명 : 단위 기능 개발 및 인프라 코드를 작성하는 분기 브랜치. (예: feature/aws-s3-backup)

### 📝 PR 제목 및 머지(Merge) 조건
- 제목 머리말 필수 지정: [Feat], [Fix], [Docs], [Refactor], [Chore]
- 보안 검증: .pem 비밀키 또는 .tfstate 파일이 하드코딩되어 올라오지 않았는지 검증
- 승인 조건: 최소 1명 이상의 팀원에게 리뷰 및 승인(Approve)을 받아야 머지 가능

---

## 🛠️ 트러블슈팅 및 성능 최적화 사례

### 1) AMI 백업 스크립트 충돌로 인한 NAT 인스턴스 패킷 드롭 및 DB 백업 실패 해결
- **문제 상황:** AWS 환경에서 정기 배포 및 관리 편의성을 위해 AMI 이미지 생성 스크립트를 실행한 이후, 프라이빗 서브넷에 위치한 데이터베이스의 원격 백업(`pg_dump` 및 S3 데이터 이관) 작업이 간헐적으로 타임아웃되며 실패하는 현상이 발생함.
- **원인 분석:** 문제 해결을 위해 퍼블릭 구간의 NAT EC2 인스턴스에 직접 SSH로 호스트 접속하여 네트워크 상태를 점검함. 분석 결과, AMI 생성 과정에서 와일드카드 자동화 스크립트가 오작동하여 NAT 인스턴스의 `iptables` 라우팅 체인 규칙을 변조했고, 이로 인해 프라이빗 서브넷에서 외부(S3 및 온프레미스 망)로 나가는 아웃바운드 패킷이 `DROP` 처리되고 있던 것을 발견함.
- **해결 조치:** NAT 인스턴스의 `iptables` 포워딩 규칙 및 NAT 테이블(`iptables -t nat -L`)을 정상 상태로 긴급 롤백하여 패킷 드롭 현상을 해결함. 이후 자동화 스크립트 내의 AMI 와일드카드 참조 범위를 명확한 태그(Tag) 기반의 명시적 서술 방식으로 수정하여 인프라 라우팅 규칙이 임의로 변조되는 재발 가능성을 원천 차단함.

### 2) CI/CD 파이프라인 내 ASG Blue-Green 배포 시 EC2 인스턴스 수 동적 관리 최적화
- **문제 상황:** GitHub Actions와 Docker Swarm/ASG를 연동하여 Blue-Green 방식의 무중단 배포를 수행하는 과정에서, 고정된 인스턴스 수를 유지할 경우 배포 전환 시점에 일시적인 자원 부족으로 컨테이너가 정상 배치되지 않거나 반대로 불필요한 비용이 낭비되는 비효율이 존재함.
- **원인 분석:** 가용 영역(AZ) 장애 시나리오나 트래픽 급증 등 인프라의 상태 변화에 따라 필요한 최소/최대 인스턴스 수가 유동적임에도 불구하고, CI/CD 스크립트가 정적 수치만을 참조하여 오토스케일링 그룹(ASG)을 제어하는 구조적 한계가 원인이었음.
- **해결 조치:** 배포 파이프라인 가동 시 현재 운영 중인 ASG의 가동 인스턴스 수(`Desired Capacity`)와 헬스 체크 상태를 AWS CLI를 통해 실시간으로 센싱하도록 스크립트를 고도화함. 새 버전 배포(Green) 시점의 시스템 부하를 고려하여 인스턴스 제한 값을 동적으로 계산 및 반영하도록 설정함으로써, 무중단 배포의 안정성을 확보하고 인프라 자원 최적화를 달성함.

### 3) 온프레미스 Ollama 분석 엔진의 LLM 버전 및 하드웨어 가속 최적화
- **문제 상황:** VMware 온프레미스 환경에 구축한 Ollama 로컬 AI 엔진이 대량의 장애 로그(Stack Trace)를 분석할 때, 문맥 추론 속도가 지나치게 느려 슬랙 알림이 지연되거나 타임아웃되는 성능 저하 현상이 발생함.
- **원인 분석:** 컨테이너 환경에서 Ollama의 특정 초기 버전이 호스트의 CPU/GPU 자원을 효율적으로 할당받지 못해 컨텍스트 윈도우가 가득 찼을 때 연산 병목이 발생하는 점을 파악함. 또한, 장애 분석 로그의 포맷에 비해 모델 크기가 무거워 토큰 생성 속도(Tokens per Second)가 저하되는 성능 한계를 확인함.
- **해결 조치:** Ollama 분석 엔진을 리소스 관리 역량이 개선된 최신 안정화 버전으로 마이그레이션하고, `docker-compose` 단에서 가상화 자원 할당량(CPU Core 및 메모리 제한)을 재조정함. 추가로 인프라 로그 분석(SRE 관점)에 가장 기민하게 반응하면서도 가벼운 경량화 모델 파라미터 세팅으로 튜닝하여, 시스템 리소스 사용량을 최소화하면서도 로그 분석 및 슬랙 알림 전송 속도를 기존 대비 대폭 향상시킴.
