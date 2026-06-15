import json
import os
import boto3
import re
import uuid
import urllib.request  # 🔥 슬랙 전송을 위한 파이썬 기본 내장 모듈
from datetime import datetime, timezone, timedelta

# 초기화
dynamodb = boto3.resource('dynamodb')
table_name = os.environ.get('DYNAMODB_TABLE', 'aidas-incidents')
slack_webhook_url = os.environ.get('SLACK_WEBHOOK_URL') # 🔥 테라폼에서 넘겨준 슬랙 URL
table = dynamodb.Table(table_name)

def lambda_handler(event, context):
    try:
        # 1. 데이터 받기
        service_name = event.get('service_name', 'UnknownService')
        raw_timestamp = event.get('timestamp', '0')
        original_log = event.get('original_log', '')
        ai_text = event.get('ai_analysis_result', '')
        elapsed = round(event.get('elapsed', 0.0), 2)
        
        # 2. 타임스탬프 변환 (KST)
        ts_sec = int(raw_timestamp) / 1_000_000_000
        kst_tz = timezone(timedelta(hours=9))
        dt_kst = datetime.fromtimestamp(ts_sec, kst_tz)
        readable_time = dt_kst.strftime('%Y-%m-%d %H:%M:%S KST')

        # 3. 데이터 파싱
        title = f"[{service_name}] 이상 징후 감지"
        cause = "분석 내용 없음"
        action = "조치 가이드 없음"

        title_match = re.search(r'\[장애 유형\]\s*:?\s*(.*)', ai_text)
        if title_match:
            title = title_match.group(1).strip()

        cause_match = re.search(r'\[발생 원인\]\s*:?\s*(.*?)(?=\[권장 조치 가이드\]|$)', ai_text, re.DOTALL)
        if cause_match:
            cause = cause_match.group(1).strip()

        action_match = re.search(r'\[권장 조치 가이드\]\s*:?\s*(.*)', ai_text, re.DOTALL)
        if action_match:
            action = action_match.group(1).strip()

        # 4. DynamoDB 저장 (DB에 이쁘게 넣기)
        item = {
            'incident_id': str(uuid.uuid4()),
            'timestamp': str(raw_timestamp),
            'status': 'OPEN',
            'severity': 'HIGH',
            'service_name': service_name,
            'Date_KST': readable_time,
            'IncidentTitle': title,
            'RootCause': cause,
            'ActionGuide': action,
            'OriginalLog': original_log,
            'AnalysisTimeSec': str(elapsed)
        }
        table.put_item(Item=item)
        print("✅ DynamoDB 저장 성공")

        # 5. 🔥 2차 슬랙 알림 전송 (이쁘게 파싱된 데이터로 쏘기)
        if slack_webhook_url:
            slack_message = {
                "text": (
                    f"🔍 *[AIDAS AI 분석 완료]*\n"
                    f"*서비스:* `{service_name}`\n"
                    f"*원본 로그:*\n```{original_log}```\n"
                    f"*AI 분석 결과:*\n"
                    f"🚨 *장애 유형:* {title}\n"
                    f"🔎 *발생 원인:* {cause}\n"
                    f"🛠️ *권장 조치:* {action}\n"
                    f"⏱ *분석 소요 시간:* {elapsed}초"
                )
            }
            req = urllib.request.Request(
                slack_webhook_url, 
                data=json.dumps(slack_message).encode('utf-8'), 
                headers={'Content-Type': 'application/json'}
            )
            urllib.request.urlopen(req)
            print("✅ Slack 2차 알림 전송 성공")

        return {
            'statusCode': 200,
            'body': json.dumps('Success: Saved to DB and sent to Slack!')
        }

    except Exception as e:
        print(f"❌ 오류 발생: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"Error: {str(e)}")
        }