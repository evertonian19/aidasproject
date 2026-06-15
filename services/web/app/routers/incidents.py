from fastapi import APIRouter, HTTPException
import logging
import time
import sys

router = APIRouter()

# 💡 [핵심 해결책] FastAPI 기본 포맷에 오염되지 않는 "순정 전용 로거"를 즉석에서 생성합니다.
raw_logger = logging.getLogger("aidas_raw_fault")
raw_logger.setLevel(logging.DEBUG)
raw_logger.propagate = False  # 상위 로거로 전달되어 접두사가 붙는 것을 원천 차단!

# 기존 핸들러가 있으면 중복 방지를 위해 제거
if raw_logger.handlers:
    raw_logger.handlers.clear()

# 오직 민규 님이 기재한 텍스트만 그대로 콘솔에 쏴주는 핸들러 설정
stream_handler = logging.StreamHandler(sys.stdout)
stream_handler.setFormatter(logging.Formatter('%(message)s'))  # 앞대가리 시간/레벨 포맷 다 제거!
raw_logger.addHandler(stream_handler)
file_handler = logging.FileHandler('/var/log/apps/aidas-test.log')
file_handler.setFormatter(logging.Formatter('%(message)s'))
raw_logger.addHandler(file_handler)



@router.post("/incident/{incident_code}")
def trigger_incident(incident_code: str):
    try:
        # ================================================================
        # 1. DB Timeout 시나리오 (순정 로그 완전 일치)
        # ================================================================
        if incident_code == "db-timeout":
            raw_logger.error("ERROR: [DB/Connection] psycopg2.OperationalError: could not connect to server at 'db.rockyai.local' — Connection timed out after 30s")
            raw_logger.error("FATAL: [DB/Pool] remaining connection slots are reserved — max_connections exhausted")
            raw_logger.warning("WARN: [DB/Retry] connection pool exhausted after 30s retry — pending_requests: 47")
            raw_logger.error("ERROR: [API] Request failed — endpoint: /api/v1/products, status: 503, reason: DB unavailable")
            raw_logger.warning("WARN: [Tailscale/VPN] Tunnel latency spike detected — src: aws-ec2, dst: rockyai-onprem, latency: 3200ms")
            
            time.sleep(3) 
            raise HTTPException(status_code=504, detail="DB Connection Timeout 모의 장애 유발 성공!")
        
        # ================================================================
        # 2. OOM (Out Of Memory) 시나리오 (순정 로그 완전 일치)
        # ================================================================
        elif incident_code == "oom":
            raw_logger.warning("WARN: [Memory] System memory critical — used: 7.8GB/8GB (97.5%), free: 201MB")
            raw_logger.error("FATAL: [OOM/Kernel] Out of memory: Kill process 3821 (python3) score 962")
            raw_logger.error("ERROR: [OOM/Kernel] Killed process 3821 (python3) — anon-rss: 5.9GB")
            raw_logger.error("ERROR: [Container] Container aidas-web-1 OOM killed — memory_limit: 512MB, usage_at_kill: 512.1MB")
            
            return {"message": "OOM 모의 장애 주입 완료!"}
        
        # ================================================================
        # 3. AZ Failure (가용 영역 장애) 시나리오 (순정 로그 완전 일치)
        # ================================================================
        elif incident_code == "az-failure":
            raw_logger.error("ERROR: [ALB/TargetGroup] Health check failed for target i-0abc123def456 (10.0.1.45:8000) in ap-northeast-2a — HTTPCode: 504, reason: timeout after 30s")
            raw_logger.error("ERROR: [EC2/Status] Instance i-0abc123def456 status check failed — SystemStatus: impaired, InstanceStatus: unreachable (AZ: ap-northeast-2a)")
            raw_logger.error("ERROR: [Network] Availability Zone ap-northeast-2a is unreachable — consecutive failures: 3/3")
            raw_logger.warning("WARN: [ALB/TargetGroup] Deregistering target i-0abc123def456 from tg-aidas-prod — reason: failed_health_checks exceeded threshold (3)")
            raw_logger.error("ERROR: [Failover] Traffic rerouting initiated — from: ap-northeast-2a (0 healthy targets) → to: ap-northeast-2c (2 healthy targets)")
            raw_logger.error("ERROR: [Service/Latency] Response latency exceeded SLA threshold — current: 5800ms, threshold: 1000ms, affected_users: ~340")
            
            time.sleep(5)
            return {"message": "AZ Failure (ap-northeast-2a) 모의 장애 주입 및 트래픽 전환 시뮬레이션 완료!"}
        
        # ================================================================
        # 4. HTTP 500 (Internal Server Error) 시나리오 (순정 로그 완전 일치)
        # ================================================================
        elif incident_code == "http500":
            raw_logger.error("ERROR: [API] Unhandled exception on endpoint /api/v1/products — ZeroDivisionError: division by zero")
            raw_logger.error("ERROR: [Traceback] File '/app/routers/products.py', line 47, in get_product_list — result = total_price / item_count")
            raw_logger.error("ERROR: [Traceback] ZeroDivisionError: division by zero — item_count evaluated to 0 (expected: int > 0)")
            raw_logger.error("ERROR: [API] Internal Server Error — endpoint: /api/v1/products, status: 500, response_time: 12ms")
            raw_logger.warning("WARN: [CI/CD] Last deployment: 2025-07-04T08:55:00Z (14min ago) — commit: a3f9e12, branch: feature/price-calc, author: leecw")
            raw_logger.error("ERROR: [Health] Service health degraded — error_rate: 94.3% (last 60s), affected_endpoint: /api/v1/products")
            
            raise HTTPException(status_code=500, detail="HTTP 500 모의 장애 유발 성공!")
            
        else:
            raise HTTPException(status_code=404, detail="알 수 없는 장애 코드입니다.")

    except HTTPException as he:
        raise he
    except Exception as e:
        raw_logger.error(f"ERROR: [System] Unexpected exception during incident processing: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))