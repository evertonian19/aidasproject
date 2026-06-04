
# 🔮🛡️ AIDAS (AI-based Incident Detection and Automated Support)
> AI 기반 장애 로그 자동 탐지 및 알림 운영 시스템
> 클라우드 컨테이너 인프라의 장애 로그를 온프레미스 로컬 AI(Ollama)로 분석하여 원인 요약과 조치 방안을 Slack으로 실시간 전달하는 지능형 관제 시스템

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
AIDAS는 퍼블릭 클라우드와 온프레미스 환경이 가상 메쉬 VPN(Tailscale)으로 유기적으로 연동된 하이브리드 인프라 아키텍처를 가집니다.

- AWS 퍼블릭 클라우드 영역 (Frontend & Web Layer) 
  Route53 / CloudFront -> ALB -> EC2 Cluster (Docker Swarm)
  * 가동 서비스: FastAPI 웹 애플리케이션 및 Promtail 에이전트 (ERROR/FATAL 로그 실시간 필터링)

- 가상 보안 터널
  * Tailscale 가상 VPN 터널을 타고 안전하게 온프레미스 환경으로 에러 로그 전송

- VMware 온프레미스 영역 (Data & AI Analytics Layer)
  * PostgreSQL (메인 데이터베이스)
  * Loki / Prometheus / Grafana (통합 관제 센터)
  * Ollama API (로컬 AI 엔진 - 외부 유출 없는 독립형 LLM 분석)

- 스마트 알림 전송
  * 가공 완료된 AI 진단 보고서 -> Slack Webhook -> 인프라 운영팀 슬랙 채널 전송



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

3) Disk Full (🟡 디스크 용량 부족)
- 동작: 서버 내부 임시 경로에 1GB 단위 더미 파일을 연속 기입하여 디스크 잔여 용량 0% 유도
- 로그: EnvironmentalError / OSError: [Errno 28] No space left on device
- AI 가이드: 오래된 로그 데이터를 AWS S3 오브젝트 스토리지로 마이그레이션하는 크론탭 스크립트 실행 권고

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
