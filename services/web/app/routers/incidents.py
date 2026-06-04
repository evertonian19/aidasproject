from fastapi import APIRouter, HTTPException
import os
import logging
import time

router = APIRouter()
logger = logging.getLogger("aidas")

@router.post("/incident/{incident_code}")
def trigger_incident(incident_code: str):
    # 📢 [핵심] 조장님 말씀대로 부학성/이재혁 님이 캐치할 표준 로그는 그대로 쾅 찍어줍니다!
    logger.error(f"[FATAL] 장애 강제 주입 시작: {incident_code}")
    
    try:
        if incident_code == "az-failure":
            # 🌐 AWS 가용 영역(AZ) 장애 시뮬레이션 (ALB 헬스체크 실패 및 트래픽 전환 재현)
            logger.error("ERROR: Health check failed for target i-0abc123def456 in ap-northeast-2a")
            logger.error("ERROR: ALB target deregistered: instance unavailable in ap-northeast-2a")
            logger.warning("WARN: Availability Zone ap-northeast-2a is unreachable")
            logger.error("ERROR: Failover triggered: rerouting traffic to ap-northeast-2c")
            logger.error("ERROR: Service degraded: response latency exceeded threshold (5000ms)")
            
            # ALB 헬스체크 지연 상황을 시뮬레이션하기 위해 5초간 대기 후 응답
            time.sleep(5)
            return {"message": "AZ Failure (ap-northeast-2a) 모의 장애 주입 및 트래픽 전환 시뮬레이션 완료!"}
        
        elif incident_code == "oom":
            # 🛡️ 안전 모드: 진짜 메모리를 터뜨리지 않고, 시뮬레이션 로그만 남깁니다.
            logger.error("[ERROR] Out Of Memory Detected! Killer process triggered for PID 4512")
            return {"message": "OOM 모의 장애 주입 완료!"}
        
        elif incident_code == "http500":
            # 🌐 500 에러는 소프트웨어 에러이므로 로그를 남기고 의도된 500 예외를 던집니다.
            logger.error("[ERROR] 서버 내부 강제 에러 발생! - HTTP 500 Internal Server Error")
            raise HTTPException(status_code=500, detail="HTTP 500 모의 장애 유발 성공!")
            
        elif incident_code == "db-timeout":
            # 🔌 타임아웃 지연 체감은 중요하므로 3초 정도로 짧게 지연 후 504를 던집니다.
            time.sleep(3) 
            logger.error("[ERROR] 504: DB Connection Timeout 유발 완료 - Connection pool exhausted")
            raise HTTPException(status_code=504, detail="DB Connection Timeout 모의 장애 유발 성공!")
            
        else:
            raise HTTPException(status_code=404, detail="알 수 없는 장애 코드입니다.")

    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"[ERROR] 장애 처리 중 예상치 못한 예외 발생: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))