#/home/user1/aidas/services/web/app/routers/incidents.py
from fastapi import APIRouter, HTTPException
import os
import logging

import time

router = APIRouter()
logger = logging.getLogger("aidas")


@router.post("/incident/{incident_code}")
def trigger_incident(incident_code: str):
    # 📢 [핵심] 조장님 말씀대로 부학성/이재혁 님이 캐치할 표준 로그는 그대로 쾅 찍어줍니다!

# 장애 주입 엔드포인트
@router.post("/incident/{incident_code}")
def trigger_incident(incident_codecode: str):

    logger.error(f"[FATAL] 장애 강제 주입 시작: {incident_code}")
    
    try:
        if incident_code == "disk-full":

            # 🛡️ 안전 모드: 진짜 파일을 쓰지 않고, 로그와 응답만 성공한 척 속입니다.
            logger.error("[ERROR] Disk 공간 고갈 임계치 초과! (Filesystem: /dev/xvda1, Usage: 99%)")
            return {"message": "Disk Full 모의 장애 주입 완료!"}
        
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

            # 1. 디스크 공간 채우기 (500MB)
            with open("/tmp/dummy_disk_fill", "wb") as f:
                f.write(os.urandom(500 * 1024 * 1024))
            return {"message": "Disk Full 장애 주입 완료!"}
        
        elif incident_code == "oom":
            # 2. 메모리 부족(OOM) 유발
            # 엄청난 크기의 리스트를 메모리에 할당
            mem_bomb = ["o" * 1024 * 1024 for _ in range(2000)]
            return {"message": "OOM 장애 주입 완료!"}
        
        elif incident_code == "http-500":
            # 3. 강제 서버 에러
            raise Exception("서버 내부 강제 에러 발생!")
            
        else:
            raise HTTPException(status_code=404, detail="알 수 없는 장애 코드입니다.")
            
    except Exception as e:
        logger.error(f"[ERROR] 장애 처리 중 예외 발생: {str(e)}")

        raise HTTPException(status_code=500, detail=str(e))