# Infra 실행 전 사전 요구사항

<br>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## ▌ PART 1. 서버 스펙 요구사항
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 제어 노드 (Ansible 명령 실행 머신)

| 항목 | 요구사항 |
|------|----------|
| OS | 임의 (Linux/macOS) |
| Ansible | Core 2.14 이상 |
| Python | 3.9 이상 |
| SSH 키 | 온프레미스 서버 / EC2 접근 가능한 키 페어 |

---

### 온프레미스 서버 (VMware)

#### 디스크 용량

| 항목 | 용량 |
|------|------|
| Ollama 바이너리 + CUDA 라이브러리 | ~3.5 GB |
| llama3 모델 | ~4.7 GB |
| qwen2.5 모델 | ~4.7 GB |
| phi3.5 모델 | ~2.2 GB |
| Docker CE + containerd | ~500 MB |
| Promtail 바이너리 | ~90 MB |
| **최소 여유 공간 (권장)** | **20 GB 이상** |

> 모델 Pull 중 디스크가 가득 차면 설치가 중단됨 — 여유 공간 충분히 확보 필수

#### 메모리 / CPU

| 항목 | 최소 | 권장 |
|------|------|------|
| RAM | 8 GB | 16 GB 이상 |
| CPU | 4 코어 | 8 코어 이상 |
| GPU | 없어도 동작 (CPU 추론) | NVIDIA GPU 권장 |

> GPU 없이 CPU 모드로 실행 시 응답 속도가 느림 (30초~수 분)

#### 네트워크

| 항목 | 내용 |
|------|------|
| 인터넷 접근 | 필수 (패키지 다운로드) |
| 포트 개방 (인바운드) | 11434 (Ollama API), 3100 (Loki), 9080 (Promtail), 3000 (Grafana) |
| Tailscale VPN | EC2 ↔ 온프레미스 통신용 |

#### Ansible이 자동 설치하는 패키지

```
# Docker 의존성
yum-utils / device-mapper-persistent-data / lvm2 / zstd / curl

# Docker CE
docker-ce / docker-ce-cli / containerd.io
docker-buildx-plugin / docker-compose-plugin

# Promtail 압축 해제
unzip
```

---

### EC2 워커 노드 (AWS)

#### 디스크 / 네트워크

| 항목 | 내용 |
|------|------|
| 최소 여유 공간 | 5 GB 이상 |
| Security Group 포트 | 22 / 80 / 443 / 2377 / 7946(TCP·UDP) / 4789(UDP) |

<br>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## ▌ PART 2. 실행 전 수동 작업
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. `inventory.ini` 에 실제 IP 입력
   - `ONPREMISE_HOST_IP` → 온프레미스 서버 실제 IP
   - EC2 워커 노드 주석 해제 후 IP 입력 (다정님 EC2 확정 후)

2. SSH 키 경로 확인
   - 온프레미스: `~/.ssh/id_rsa`
   - EC2: `~/.ssh/aidas-ec2-key.pem`

3. 온프레미스 서버 `sudo` 권한 확인
   ```bash
   ssh rocky@<ONPREMISE_IP> "sudo whoami"
   # 출력: root
   ```

<br>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## ▌ PART 3. 로컬 테스트 가이드
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 전제 조건 — playbook.yml hosts 확인

```yaml
# 테스트 중
hosts: localhost  ### 테스트는 localhost로 진행후에 변경 예정입니다

# 실제 배포 시
hosts: onpremise
```

> **모든 명령은 `infra/ansible/` 안에서 실행** (templates/ 상대경로 참조)

---

### 어느 터미널에서 실행하는가

| 현재 위치 | 이동 명령 |
|-----------|-----------|
| `project/` | `cd infra/ansible` |
| `project/infra/` | `cd ansible` |
| `project/infra/ansible/` | 이동 불필요 |

---

### 0단계 — 테스트용 임시 인벤토리 생성 (최초 1회)

```bash
cat > /tmp/test-inventory.ini << 'EOF'
[onpremise]
localhost ansible_connection=local ansible_python_interpreter=/usr/bin/python3

[all:vars]
loki_host=127.0.0.1
EOF
```

### 1단계 — 문법 검사

```bash
ansible-playbook playbook.yml -i /tmp/test-inventory.ini --syntax-check
```

### 2단계 — 실제 실행

```bash
# 전체 실행 (모델 3개 모두 Pull)
ansible-playbook playbook.yml -i /tmp/test-inventory.ini

# 모델 Pull 스킵 (이미 설치된 경우)
ansible-playbook playbook.yml -i /tmp/test-inventory.ini \
  --skip-tags llama3_pull,qwen_pull,phi_pull
```

### 3단계 — 멱등성 검증 (재실행)

```bash
ansible-playbook playbook.yml -i /tmp/test-inventory.ini \
  --skip-tags llama3_pull,qwen_pull,phi_pull

# PLAY RECAP: changed=0 이어야 정상
```

### 4단계 — 테스트 완료 후 정리

```bash
# cleanup.yml 으로 전체 제거
ansible-playbook cleanup.yml -i /tmp/test-inventory.ini

# 임시 인벤토리 삭제
rm /tmp/test-inventory.ini
```

---

### 테스트 결과 판단 기준

| 항목 | 정상 | 비정상 |
|------|------|--------|
| failed | 0 | 1 이상 → 에러 메시지 확인 |
| 재실행 시 changed | 0 | 1 이상 → 멱등성 깨짐 |
| unreachable | 0 | 1 이상 → SSH 연결 문제 |

<br>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## ▌ PART 3-1. 설치 확인 명령어
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Docker 확인

```bash
docker --version
systemctl is-active docker
docker run --rm hello-world
```

---

### Ollama 확인

```bash
# 한 줄 통합 확인
which ollama && ollama --version && systemctl is-active ollama && curl -s http://127.0.0.1:11434/

# 설치된 모델 목록
ollama list
```

---

### Promtail 확인

```bash
# 바이너리 존재 확인
which promtail

# 서비스 상태
systemctl is-active promtail

# 설정 파일 확인
cat /etc/promtail/config.yml
```

---

### 모델 추론 테스트

```bash
# llama3 기반 커스텀 모델
ollama run aidas-sre "OSError: [Errno 28] No space left on device"

# qwen2.5 기반 커스텀 모델
ollama run aidas-sre-qwen "OSError: [Errno 28] No space left on device"

# phi3.5 기반 커스텀 모델
ollama run aidas-sre-phi "OSError: [Errno 28] No space left on device"
```

API로 두 모델 동시 비교:
```bash
for model in aidas-sre aidas-sre-qwen aidas-sre-phi; do
  echo "=== $model ==="
  curl -s http://127.0.0.1:11434/api/generate \
    -d "{\"model\":\"$model\",\"prompt\":\"OSError: [Errno 28] No space left on device\",\"stream\":false}" \
    | python3 -c "import sys,json; print(json.load(sys.stdin)['response'])"
done
```

<br>

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## ▌ PART 4. 실제 서버 배포 명령어
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

> 플레이북 완성 후 `hosts: localhost` → `hosts: onpremise` 변경 후 실행

```bash
# 실행 위치: infra/ansible/

# 전체 실행
ansible-playbook playbook.yml -i inventory.ini

# 모델 Pull 스킵
ansible-playbook playbook.yml -i inventory.ini \
  --skip-tags llama3_pull,qwen_pull,phi_pull

# 특정 호스트만
ansible-playbook playbook.yml -i inventory.ini --limit onpremise

# 문법 검사
ansible-playbook playbook.yml -i inventory.ini --syntax-check

# 전체 제거
ansible-playbook cleanup.yml -i inventory.ini
```
