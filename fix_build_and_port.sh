#!/usr/bin/env bash
set -euo pipefail

# ===== 설정(필요 시 외부에서 export) =====
GIT_REMOTE_URL="${GIT_REMOTE_URL:-}"               # 예) https://github.com/<ORG_OR_USER>/<REPO>.git
RAILWAY_TOKEN="${RAILWAY_TOKEN:-}"                 # Railway Personal Token
RAILWAY_SERVICE="${RAILWAY_SERVICE:-emark-des}"
CACHE_BUST="${CACHE_BUST:-$(date +%s)}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
STREAM_TEST_Q="${STREAM_TEST_Q:-ping}"
APP_URL="${APP_URL:-}"                              # 배포 URL 있으면 헬스/SSE 확인

# ===== 사전 체크 =====
[[ -f Dockerfile ]] || { echo "❌ Dockerfile not found at repo root"; exit 1; }
[[ -d app/src ]] || { echo "❌ app/src not found (run in monorepo root)"; exit 1; }

# ===== 1) api.ts 존재 보장 =====
mkdir -p app/src/lib
API_TS="app/src/lib/api.ts"
if [[ ! -f "$API_TS" ]]; then
cat > "$API_TS" <<'TS'
const API_BASE = import.meta.env.VITE_API_BASE || "";

export function startStream(question: string, onMessage:(d:any)=>void, onEnd?:()=>void) {
  const url = `${API_BASE}/api/stream?question=${encodeURIComponent(question)}`.replace('//api','/api');
  const es = new EventSource(url);
  es.onmessage = (ev) => { try { onMessage(JSON.parse(ev.data)); } catch {} };
  es.onerror = () => { es.close(); onEnd?.(); };
  return () => es.close();
}

export async function askTop(session:any, prompt?:string) {
  const res = await fetch(`${API_BASE}/api/askTop`.replace('//api','/api'), {
    method:"POST", headers:{ "Content-Type":"application/json" },
    body: JSON.stringify({ session, prompt })
  });
  return await res.json();
}
TS
  echo "✅ Added $API_TS"
else
  echo "ℹ️  $API_TS already exists"
fi

# ===== 2) Dockerfile: webbuild 캐시버스트 + 디버그 RUN =====
if ! grep -Fq 'ARG CACHE_BUST' Dockerfile; then
  awk -v stamp="$CACHE_BUST" '
    BEGIN{done=0}
    {print}
    /^FROM .* AS webbuild/ && !done { print "ARG CACHE_BUST=" stamp; print "RUN echo \"CACHE_BUST=" stamp "\""; done=1 }
  ' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Added ARG CACHE_BUST to webbuild"
fi

if ! grep -q "Web stage tree" Dockerfile; then
  perl -0777 -pe 's/RUN npm run build/RUN echo \"--- Web stage tree ---\" \&\& ls -la \&\& echo \"--- src ---\" \&\& ls -la src \|\| true \&\& echo \"--- src\/lib ---\" \&\& ls -la src\/lib \|\| true \&\& echo \"--- App.tsx head ---\" \&\& head -n 20 src\/App.tsx \|\| true \n\nRUN npm run build/;' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Added debug listing before Vite build"
fi

# ===== 3) Dockerfile: Gunicorn CMD를 sh -c로 (PORT 확장) =====
if grep -q '^CMD \["gunicorn' Dockerfile; then
  perl -0777 -pe 's#^CMD \[.*gunicorn[^\n]*\]\s*$#CMD ["sh","-c","gunicorn -k gevent -w \\${WORKERS:-1} --access-logfile - --error-logfile - -t 0 -b 0.0.0.0:\\${PORT} app:app"]#m;' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Replaced exec-form CMD with sh -c (PORT expansion)"
elif grep -q '^CMD \["sh","-c"' Dockerfile; then
  perl -0777 -pe 's#^CMD \["sh","-c",.*\]\s*$#CMD ["sh","-c","gunicorn -k gevent -w \\${WORKERS:-1} --access-logfile - --error-logfile - -t 0 -b 0.0.0.0:\\${PORT} app:app"]#m;' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Updated sh -c CMD to bind 0.0.0.0:\${PORT}"
else
  cat >> Dockerfile <<'DOCKER'
CMD ["sh","-c","gunicorn -k gevent -w \${WORKERS:-1} --access-logfile - --error-logfile - -t 0 -b 0.0.0.0:\${PORT} app:app"]
DOCKER
  echo "✅ Added sh -c CMD for Gunicorn"
fi

# ===== 4) railway.toml (명시적 빌드) =====
if [[ ! -f railway.toml ]]; then
cat > railway.toml <<'TOML'
[build]
builder = "DOCKERFILE"
dockerfilePath = "./Dockerfile"
TOML
  echo "✅ Created railway.toml"
fi

# ===== 5) Git 커밋/푸시 (옵션) =====
if [[ -n "${GIT_REMOTE_URL}" ]]; then
  [[ -d .git ]] || { git init && git checkout -b main; }
  git add .
  git commit -m "chore: fix api.ts & PORT expansion; add webbuild debug/cache-bust/railway.toml" || true
  git remote | grep -q origin || git remote add origin "${GIT_REMOTE_URL}"
  git push -u origin main
  echo "✅ Pushed to ${GIT_REMOTE_URL}"
fi

# ===== 6) Railway 배포 (로그인 호출 없이 전역 --token 사용) =====
if [[ -n "${RAILWAY_TOKEN}" ]]; then
  command -v railway >/dev/null 2>&1 || npm i -g @railway/cli
  railway --token "${RAILWAY_TOKEN}" up --service "${RAILWAY_SERVICE}"
  echo "🚀 Railway deploy triggered (service=${RAILWAY_SERVICE})"
else
  echo "ℹ️  RAILWAY_TOKEN not set; skip deploy"
fi

# ===== 7) 헬스 & 스트림 검사 (옵션) =====
if [[ -n "${APP_URL}" ]]; then
  echo "⏳ wait 10s"; sleep 10
  echo "➡️  GET ${APP_URL}${HEALTH_PATH}"
  curl -fsS "${APP_URL}${HEALTH_PATH}" || true
  echo -e "\n➡️  SSE test: ${APP_URL}/api/stream?question=${STREAM_TEST_Q} (first few lines)"
  curl -N --max-time 10 "${APP_URL}/api/stream?question=${STREAM_TEST_Q}" | head -n 6 || true
fi

echo "✅ Done."

