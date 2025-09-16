#!/usr/bin/env bash
set -euo pipefail
REPO_URL="${1:-}"
if [[ -z "${REPO_URL}" ]]; then
  echo "사용법: scripts/init_repo.sh <GITHUB_REPO_URL>"
  exit 1
fi

git init
git add .
git commit -m "feat: Emark DES 초기 커밋 (Flask SSE + React + Docker)"
git branch -M main
git remote add origin "$REPO_URL"
git push -u origin main
echo "✅ GitHub 푸시 완료: $REPO_URL"
