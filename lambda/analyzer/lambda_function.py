import json
import os
import boto3
import urllib.request
from datetime import datetime, timezone

# ─── 환경변수 ──────────────────────────────────────────────────────
SLACK_WEBHOOK_URL = os.environ["SLACK_WEBHOOK_URL"]
DYNAMODB_TABLE    = os.environ.get("DYNAMODB_TABLE", "aidas-incidents")
AWS_REGION        = os.environ.get("AWS_REGION", "ap-northeast-2")

dynamodb = boto3.resource("dynamodb", region_name=AWS_REGION)
table    = dynamodb.Table(DYNAMODB_TABLE)



def get_timestamp() -> str:
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}Z"


def send_slack(original_log: str, analysis: str, elapsed: float):
    try:
        message = {
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": "🔍 AIDAS AI 분석 완료"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*원본 로그*\n```\n{original_log}\n```"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": f"*AI 분석 결과*\n{analysis}"
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": f"⏱ 분석 소요 시간: {elapsed:.2f}초"
                        }
                    ]
                }
            ]
        }
        req = urllib.request.Request(
            SLACK_WEBHOOK_URL,
            data    = json.dumps(message).encode("utf-8"),
            headers = {"Content-Type": "application/json"},
            method  = "POST"
        )
        with urllib.request.urlopen(req) as res:
            print(f"[AIDAS] Slack 전송 완료: {res.status}")

    except Exception as e:
        print(f"[AIDAS] Slack 전송 실패: {e}")


def save_dynamodb(original_log: str, analysis: str, timestamp: str, service_name: str):
    try:
        table.put_item(
            Item={
                "incident_id":       f"incident-{timestamp}",
                "timestamp":         timestamp,
                "incident_status":   "detected",
                "incident_severity": "ERROR",
                "service_name":      service_name,
                "original_log":      original_log,
                "analysis":          analysis
            }
        )
        print("[AIDAS] DynamoDB 저장 완료")

    except Exception as e:
        print(f"[AIDAS] DynamoDB 저장 실패: {e}")


def lambda_handler(event, context):
    original_log = event.get("original_log", "")
    analysis     = event.get("ai_analysis_result", "")
    elapsed      = event.get("elapsed", 0.0)
    service_name = event.get("service_name", "unknown")
    timestamp = event.get("timestamp") or get_timestamp()


    send_slack(original_log, analysis, elapsed)


    save_dynamodb(original_log, analysis, timestamp, service_name)

    return {"statusCode": 200, "body": "OK"}