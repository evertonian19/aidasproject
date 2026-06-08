# 로그 분석 파이프라인 문서

Loki를 거쳐 Lambda, Ollama AI, Slack까지 도달하는 실시간 흐름 문서입니다.

---

## 전체 흐름 요약

```
EC2 FastAPI
→ Promtail (ERROR/FATAL/WARN 필터링)
→ Loki (로그 저장)
→ handler.py (5초마다 폴링)
→ Ollama AI (로그 분석)
→ Lambda (boto3 호출)
→ Slack 알림 + DynamoDB 저장
```

---

## 구성 요소별 역할

### 1. FastAPI (AWS EC2)
- 미니 커머스 웹 서비스 운영
- 4대 장애 시나리오 버튼 클릭 시 에러 로그 출력
- 로그 포맷: `[ERROR/WARN/FATAL] [컴포넌트] 메시지`

### 2. Promtail (AWS EC2)
- FastAPI 로그 파일 실시간 테일링
- `ERROR`, `WARN`, `FATAL`, `CRITICAL` 키워드만 필터링
- Tailscale VPN을 통해 Loki로 전송

### 3. Loki (rocky01 온프레미스)
- Promtail이 보낸 에러 로그 수신 및 저장
- 포트: `3100`
- handler.py가 `/loki/api/v1/query_range` API로 폴링

### 4. handler.py (rocky01 온프레미스)
- APScheduler로 **5초마다** Loki API 폴링
- `last_processed_ts`로 중복 로그 방지
- **15초 컨텍스트 윈도우**로 관련 로그 묶음 처리
- 시나리오 자동 판별 후 Ollama 호출

```python
# 시나리오 판별 키워드
DB Timeout  → "DB/Connection", "DB/Pool", "psycopg2"
OOM         → "OOM/Kernel", "[Memory]", "OOM killed"
AZ Failure  → "ALB/TargetGroup", "Failover", "ap-northeast-2a"
HTTP 500    → "Traceback", "ZeroDivisionError", "Internal Server Error"
```

### 5. Ollama AI (rocky01 온프레미스)
- 모델: `qwen2.5-coder:7b`
- 포트: `11434`
- `system_prompt.txt` + 시나리오별 `scenarios/*.txt` 합쳐서 분석
- `<thinking>` 태그 제거 후 결과 반환
- 옵션: `num_predict: 512`, `temperature: 0.1`, `top_p: 0.9`

### 6. Lambda (AWS)
- handler.py가 boto3로 비동기 호출
- 함수명: `aidas-slack-alert`
- **Slack 전송** + **DynamoDB 저장** 담당

### 7. Slack
- 운영팀 채널로 AI 분석 결과 실시간 전송
- 포맷: 원본 로그 + AI 분석 결과 + 소요 시간

### 8. DynamoDB
- 장애 이력 저장 (테이블: `aidas-incidents`)
- 저장 항목: `incident_id`, `timestamp`, `incident_status`, `incident_severity`, `original_log`, `analysis`

---

## 장애 시나리오별 로그

### DB Timeout
```
ERROR: [DB/Connection] psycopg2.OperationalError: could not connect to server at 'db.rockyai.local' — Connection timed out after 30s
FATAL: [DB/Pool] remaining connection slots are reserved — max_connections exhausted
WARN:  [DB/Retry] connection pool exhausted after 30s retry — pending_requests: 47
ERROR: [API] Request failed — endpoint: /api/v1/products, status: 503, reason: DB unavailable
WARN:  [Tailscale/VPN] Tunnel latency spike detected — src: aws-ec2, dst: rockyai-onprem, latency: 3200ms
```

### OOM
```
WARN:  [Memory] System memory critical — used: 7.8GB/8GB (97.5%), free: 201MB
FATAL: [OOM/Kernel] Out of memory: Kill process 3821 (python3) score 962
ERROR: [OOM/Kernel] Killed process 3821 (python3) — anon-rss: 5.9GB
ERROR: [Container] Container aidas-web-1 OOM killed — memory_limit: 512MB, usage_at_kill: 512.1MB
```

### AZ Failure
```
ERROR: [ALB/TargetGroup] Health check failed for target i-0abc123def456 (10.0.1.45:8000) in ap-northeast-2a — HTTPCode: 504, reason: timeout after 30s
ERROR: [EC2/Status] Instance i-0abc123def456 status check failed — SystemStatus: impaired, InstanceStatus: unreachable (AZ: ap-northeast-2a)
ERROR: [Network] Availability Zone ap-northeast-2a is unreachable — consecutive failures: 3/3
ERROR: [Failover] Traffic rerouting initiated — from: ap-northeast-2a (0 healthy targets) → to: ap-northeast-2c (2 healthy targets)
ERROR: [Service/Latency] Response latency exceeded SLA threshold — current: 5800ms, threshold: 1000ms, affected_users: ~340
```

### HTTP 500
```
ERROR: [API] Unhandled exception on endpoint /api/v1/products — ZeroDivisionError: division by zero
ERROR: [Traceback] File '/app/routers/products.py', line 47, in get_product_list — result = total_price / item_count
ERROR: [Traceback] ZeroDivisionError: division by zero — item_count evaluated to 0 (expected: int > 0)
ERROR: [API] Internal Server Error — endpoint: /api/v1/products, status: 500, response_time: 12ms
WARN:  [CI/CD] Last deployment: 2025-07-04T08:55:00Z (14min ago) — commit: a3f9e12, branch: feature/price-calc, author: leecw
ERROR: [Health] Service health degraded — error_rate: 94.3% (last 60s), affected_endpoint: /api/v1/products
```

---

## 소요 시간 (SLA 목표: 60초 이내)

| 단계 | 소요 시간 |
|---|---|
| Loki 폴링 감지 | 최대 5초 |
| Ollama AI 분석 | 30~50초 |
| Lambda 호출 | ~1초 |
| Slack 전송 | ~1초 |
| **총 소요 시간** | **약 35~55초** |

---

## AI 분석 실패 시 보험 처리

```
Ollama 분석 실패
→ Lambda 호출 생략
→ handler.py에서 Slack으로 원본 로그 직접 전송
→ "AI 분석 실패, 원본 로그만 발송" 메시지
```

---

## 파일 구조

```
aidas/
├── lambda/analyzer/
│   ├── handler.py           # 메인 파이프라인
│   ├── lambda_function.py   # Slack + DynamoDB
│   └── requirements.txt
└── prompts/
    ├── system_prompt.txt    # 공통 프롬프트
    └── scenarios/
        ├── db_timeout.txt   # DB 장애 시나리오
        ├── oom.txt          # OOM 장애 시나리오
        ├── az_failure.txt   # AZ 장애 시나리오
        └── http_500.txt     # HTTP 500 시나리오
```