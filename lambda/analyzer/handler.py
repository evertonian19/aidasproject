import os
import json
import httpx
import asyncio
import boto3
import re
import logging
import time
from datetime import datetime, timedelta
from apscheduler.schedulers.asyncio import AsyncIOScheduler
from dotenv import load_dotenv

load_dotenv()

logger = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO)

LOKI_URL = os.getenv("LOKI_URL", "http://localhost:3100")
OLLAMA_API_URL = os.getenv("OLLAMA_API_URL", "http://localhost:11434/api/generate")
AI_MODEL_NAME = "qwen2.5-coder:7b"
SLACK_WEBHOOK_URL = os.getenv("SLACK_WEBHOOK_URL")

AWS_REGION = os.getenv("AWS_REGION", "ap-northeast-2")
LAMBDA_FUNCTION_NAME = os.getenv("LAMBDA_FUNCTION_NAME", "aidas-slack-alert")
lambda_client = boto3.client('lambda', region_name=AWS_REGION)
PROMPT_PATH = os.getenv("PROMPT_PATH", "/home/user1/aidas/prompts/system_prompt.md")
SCENARIO_PATH = "/home/user1/aidas/prompts/scenarios"

# 전역 변수를 서비스별 격리가 가능한 딕셔너리 구조로 변경
last_processed_ts = {}


def get_system_prompt():
    try:
        with open(PROMPT_PATH, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        logger.warning(f"🚨 {PROMPT_PATH} 파일이 없습니다.")
        return "너는 시스템 에러를 분석하는 AI 엔지니어다."


def trigger_lambda_sync(log_data: dict, clean_ai_analysis: str, elapsed: float):
    payload = {
        "service_name":       log_data.get("service_name"),
        "timestamp":          log_data.get("timestamp"),
        "original_log":       log_data.get("message"),
        "ai_analysis_result": clean_ai_analysis,
        "elapsed":            elapsed
    }
    try:
        lambda_client.invoke(
            FunctionName=LAMBDA_FUNCTION_NAME,
            InvocationType='Event',
            Payload=json.dumps(payload)
        )
        logger.info("✅ AWS Lambda(boto3) 트리거 완료 -> Slack/DynamoDB 진행됨")
    except Exception as e:
        logger.error(f"❌ AWS Lambda 호출 실패: {e}")


# ── 1차 알림: 원본 로그 즉시 발송 ─────────────────────────────────
async def send_slack_immediate_alert(log_data: dict):
    payload = {
        "text": (
            f"🚨 *[AIDAS 장애 감지]*\n"
            f"*서비스:* `{log_data.get('service_name')}`\n"
            f"*원본 로그:*\n```{log_data.get('message')}```\n"
            f"⏳ AI 분석 중..."
        )
    }
    async with httpx.AsyncClient() as client:
        await client.post(SLACK_WEBHOOK_URL, json=payload)
    logger.info("✅ 1차 Slack 알림 발송 완료 (원본 로그)")


# ── 2차 알림 fallback: AI 분석 실패 시 ────────────────────────────
async def send_slack_fallback_alert(log_data: dict, error_reason: str):
    payload = {
        "text": (
            f"⚠️ *[AIDAS AI 분석 실패]*\n"
            f"*에러 내용:* `{log_data.get('message')}`\n"
            f"*실패 사유:* {error_reason}"
        )
    }
    async with httpx.AsyncClient() as client:
        await client.post(SLACK_WEBHOOK_URL, json=payload)


def detect_scenario(log_message: str) -> str:
    if any(kw in log_message for kw in ["DB/Connection", "DB/Pool", "DB/Retry", "psycopg2"]):
        return "db_timeout"
    elif any(kw in log_message for kw in ["OOM/Kernel", "Memory", "OOM killed"]):
        return "oom"
    elif any(kw in log_message for kw in ["ALB/TargetGroup", "Failover", "ap-northeast-2a"]):
        return "az_failure"
    elif any(kw in log_message for kw in ["Traceback", "ZeroDivisionError", "Internal Server Error"]):
        return "http_500"
    else:
        return "unknown"


def load_scenario_prompt(scenario: str) -> str:
    path = f"{SCENARIO_PATH}/{scenario}.md"
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except FileNotFoundError:
        return ""


async def analyze_with_ai(log_message: str):
    system_prompt = get_system_prompt()
    scenario = detect_scenario(log_message)
    scenario_prompt = load_scenario_prompt(scenario)
    logger.info(f"[AIDAS] 감지된 시나리오: {scenario}")

    full_prompt = f"{system_prompt}\n\n{scenario_prompt}\n\n[분석할 에러 로그]\n{log_message}"
    full_response = ""

    try:
        async with httpx.AsyncClient() as client:
            async with client.stream("POST", OLLAMA_API_URL, json={
                "model": AI_MODEL_NAME,
                "prompt": full_prompt,
                "stream": True,
                "options": {
                    "num_predict": 512,
                    "temperature": 0.1,
                    "top_p": 0.9
                }
            }, timeout=120.0) as response:
                async for chunk in response.aiter_text():
                    if chunk:
                        try:
                            data = json.loads(chunk)
                            full_response += data.get("response", "")
                        except json.JSONDecodeError:
                            pass

        clean_response = re.sub(r'<thinking>.*?</thinking>', '', full_response, flags=re.DOTALL).strip()
        return clean_response
    except Exception as e:
        raise e


async def poll_loki_and_analyze():
    global last_processed_ts

    # 서버 간 미세한 시간 차이를 방어하기 위해 검색 윈도우를 넉넉하게 10분으로 확장
    end_time = datetime.utcnow()
    start_time = end_time - timedelta(seconds=600)

    # 대소문자 구분 없이 Nginx와 백엔드 오류를 통합 탐색하기 위해 (?i) 정규식 플래그 주입
    query = '{job=~".+"} |~ "(?i)error|fatal|warn"'

    params = {
        'query': query,
        'start': str(int(start_time.timestamp() * 1e9)),
        'end': str(int(end_time.timestamp() * 1e9)),
        'limit': 100
    }

    try:
        async with httpx.AsyncClient() as client:
            resp = await client.get(f"{LOKI_URL}/loki/api/v1/query_range", params=params)
            resp.raise_for_status()
            data = resp.json()

        results = data.get('data', {}).get('result', [])

        # 수집 주기에 걸린 로그들을 서비스명 단위로 집적할 임시 바구니
        logs_by_service = {}

        for res in results:
            service_name = res.get('stream', {}).get('job', 'unknown')
            values = sorted(res.get('values', []), key=lambda x: int(x[0]))

            # 각 서비스 ID에 독립적으로 매핑된 직전 처리 타임스탬프 로드
            service_last_ts = last_processed_ts.get(service_name, 0)
            max_ts_in_batch = service_last_ts

            for timestamp_str, message in values:
                ts_int = int(timestamp_str)
                if ts_int <= service_last_ts:
                    continue
                
                # 중복되지 않은 신규 로그들을 서비스 바구니에 담기
                if service_name not in logs_by_service:
                    logs_by_service[service_name] = {"messages": [], "max_ts": 0}
                    
                logs_by_service[service_name]["messages"].append(message)
                logs_by_service[service_name]["max_ts"] = max(logs_by_service[service_name]["max_ts"], ts_int)
                max_ts_in_batch = max(max_ts_in_batch, ts_int)

            # 스트림 데이터 분류 완료 후 전역 변수 업데이트 준비
            if service_name in logs_by_service:
                last_processed_ts[service_name] = max(last_processed_ts.get(service_name, 0), max_ts_in_batch)

        # 수집이 끝난 바구니의 묶음 데이터들을 순차적으로 슬랙 및 람다 인터페이스로 전송
        for service_name, data in logs_by_service.items():
            if data["messages"]:
                combined_message = "\n".join(data["messages"])
                max_ts = data["max_ts"]
                
                log_data = {
                    "service_name": service_name,
                    "timestamp": str(max_ts),
                    "message": combined_message
                }

                logger.info(f"🚨 신규 에러 {len(data['messages'])}건 묶음 감지! ([{service_name}]) 1차 알림 발송...")

                await send_slack_immediate_alert(log_data)

                try:
                    start = time.time()
                    clean_analysis = await analyze_with_ai(combined_message)
                    elapsed = time.time() - start
                    trigger_lambda_sync(log_data, clean_analysis, elapsed)
                except Exception as ai_e:
                    await send_slack_fallback_alert(log_data, str(ai_e))

    except Exception as e:
        logger.error(f"Loki 폴링 실패: {e}")


async def main():
    logger.info("AIDAS Log Analyzer 시작됨 (5초 주기)")
    scheduler = AsyncIOScheduler()
    scheduler.add_job(poll_loki_and_analyze, 'interval', seconds=5)
    scheduler.start()
    await asyncio.Event().wait()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except (KeyboardInterrupt, SystemExit):
        logger.info("핸들러 안전하게 종료됨")