# Emark DES — AI 토론 평점 시스템 (Flask SSE + React + Docker)

## 빠른 시작
```bash
make build      # 프런트 빌드 → server/static 복사
make run        # 로컬 실행 (http://localhost:8000)
```

## Docker
```bash
make docker-build
# 실행 예시:
# docker run -e PORT=8000 -p 8000:8000 emark-des:latest
```

## GitHub 업로드
```bash
bash scripts/init_repo.sh <GITHUB_REPO_URL>
```

## Railway 배포 (GitHub Actions 사용 권장)
1) GitHub 리포지토리 Secrets 추가: `RAILWAY_TOKEN`
2) push → GitHub Actions가 `railway up` 실행
또는 수동:
```bash
export RAILWAY_TOKEN=xxx
bash scripts/deploy_railway.sh
```

## 실키 연동(선택)
`.env` 또는 Railway 환경변수:
```
ENABLE_REAL_CALLS=true
OPENAI_API_KEY=...
GEMINI_API_KEY=...
XAI_API_KEY=...
ANTHROPIC_API_KEY=...
```
