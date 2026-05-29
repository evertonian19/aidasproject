🤝 AIDAS 협업 가이드 (Contributing Guide)
이 문서는 쉬지마EC 2 팀이 AIDAS 프로젝트를 함께 개발하기 위한 협업 규칙입니다.
작업을 시작하기 전에 반드시 한 번 읽어주세요.

1. 브랜치 전략 (Branch Strategy)
브랜치역할설명master배포 본진가장 안정적인 배포용 브랜치. 직접 push 금지 (PR로만 반영)develop통합 개발다음 버전을 위해 개발 내용을 통합하는 메인 베이스 브랜치feature/기능명단위 작업기능 개발·인프라 코드를 작성하는 분기 브랜치
브랜치 네이밍 규칙

형식: feature/작업내용
예시: feature/aws-vpc-terraform, feature/incident-injector, feature/ollama-prompt


모든 작업은 feature/ 브랜치에서 시작합니다. master와 develop에는 절대 직접 작업하지 않습니다.


2. 커밋 & PR 제목 컨벤션
커밋 메시지와 PR 제목 앞에는 아래 머리말을 반드시 붙입니다.
머리말용도[Feat]새로운 기능 추가[Fix]버그 수정[Docs]문서 수정 (README, docs 등)[Refactor]코드 리팩토링 (기능 변경 없음)[Chore]빌드·패키지·설정 등 잡무[Infra]인프라 코드 수정 (Terraform, Ansible, Docker 등)
예시: [Feat] 상품 목록 조회 API 구현, [Infra] Terraform VPC 모듈 추가

3. 작업 흐름 (Workflow)
Step 1. 최신 develop 받기
작업 시작 전 항상 develop을 최신 상태로 맞춥니다.
bashgit checkout develop
git pull origin develop
Step 2. feature 브랜치 따기
bashgit checkout -b feature/작업명
Step 3. 작업 후 커밋
bashgit add .  
git commit -m "[Feat] 작업 내용 요약"

⚠️ 커밋 전에 .pem, .tfstate, .env 같은 민감 파일이 포함되지 않았는지 git status로 확인하세요.

Step 4. 원격에 push
bashgit push -u origin feature/작업명
Step 5. Pull Request 생성

GitHub에서 Compare & pull request 버튼 클릭
base 브랜치는 develop, compare는 본인 feature/ 브랜치로 설정
PR 템플릿이 자동으로 뜨면 항목을 채웁니다.

Step 6. 리뷰 & 머지

최소 1명 이상의 팀원에게 리뷰 및 승인(Approve)을 받아야 머지 가능
승인 후 develop으로 머지
충분히 검증된 develop 내용만 추후 master로 반영


4. Pull Request 규칙

PR 제목에 머리말([Feat] 등) 필수
PR 템플릿의 체크리스트를 성실히 작성
머지 조건: 리뷰어 1명 이상 승인
master 브랜치는 Branch Protection이 걸려 있어 PR 없이 머지 불가


5. 🛡️ 보안 규칙 (필독)
아래 파일은 절대 커밋·push 금지입니다. (.gitignore로 차단되어 있으나 반드시 직접 확인)

*.pem, *.key — SSH 개인키 / 인증서
*.tfstate, *.tfvars — Terraform 상태 파일 (AWS 자격증명 평문 포함 위험)
.env — Slack Webhook URL, DB 비밀번호 등 환경변수


환경변수가 필요할 때는 실제 .env 대신 키 이름만 적힌 .env.example을 참고하세요.
민감 정보가 실수로 커밋됐다면 즉시 팀에 공유하고, 해당 키는 폐기·재발급해야 합니다.


6. 충돌(Conflict)이 났을 때
bashgit checkout develop
git pull origin develop
git checkout feature/작업명
git merge develop
# 충돌 해결 후
git add .
git commit -m "[Fix] develop 머지 충돌 해결"
git push