#!/usr/bin/env bash
set -euo pipefail
if ! command -v railway >/dev/null 2>&1; then
  npm i -g @railway/cli
fi

if [[ -z "${RAILWAY_TOKEN:-}" ]]; then
  echo "RAILWAY_TOKEN 환경변수가 필요합니다."
  exit 1
fi

railway login --token "$RAILWAY_TOKEN"
railway up --service emark-des
echo "✅ Railway 배포 요청 완료"
