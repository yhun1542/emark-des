#!/usr/bin/env bash
set -euo pipefail

# =========================
# Emark DES one-shot fixer
# - Fix Vite build (ensure app/src/lib/api.ts)
# - Fix Gunicorn PORT expansion in Dockerfile
# - Add webbuild debug + cache-bust
# - (Optional) create railway.toml for monorepo
# - Commit & push
# - (Optional) Railway deploy & health check
# =========================

# ---- CONFIG (envs override) ----
GIT_REMOTE_URL="${GIT_REMOTE_URL:-}"          # e.g. https://github.com/<ORG_OR_USER>/<REPO>.git
RAILWAY_TOKEN="${RAILWAY_TOKEN:-}"            # railway token (optional)
RAILWAY_SERVICE="${RAILWAY_SERVICE:-emark-des}"
CACHE_BUST="${CACHE_BUST:-$(date +%s)}"
HEALTH_PATH="${HEALTH_PATH:-/health}"
STREAM_TEST_Q="${STREAM_TEST_Q:-ping}"

# ---- Sanity checks ----
if [[ ! -f "Dockerfile" ]]; then
  echo "❌ Dockerfile not found at repo root. Run this in repo root."
  exit 1
fi
if [[ ! -d "app/src" ]]; then
  echo "❌ app/src not found. Are you in the monorepo root?"
  exit 1
fi

# ---- Step 1: ensure app/src/lib/api.ts exists ----
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
    method:"POST",
    headers:{ "Content-Type":"application/json" },
    body: JSON.stringify({ session, prompt })
  });
  return await res.json();
}
TS
  echo "✅ Added $API_TS"
else
  echo "ℹ️  $API_TS already exists (keeping)"
fi

# ---- Step 2: patch Dockerfile webbuild stage (cache-bust + debug ls) ----
if ! grep -q 'ARG CACHE_BUST' Dockerfile; then
  # Insert ARG after FROM node:... AS webbuild
  awk '
    BEGIN{done=0}
    {
      print $0
      if ($0 ~ /^FROM .* AS webbuild/ && done==0) {
        print "ARG CACHE_BUST=1"
        print "RUN echo \"CACHE_BUST=${CACHE_BUST}\""
        done=1
      }
    }' CACHE_BUST="$CACHE_BUST" Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Added ARG CACHE_BUST to webbuild stage"
else
  echo "ℹ️  Dockerfile already has ARG CACHE_BUST"
fi

# Ensure debug listing once before npm run build
if ! grep -q '--- Web stage tree ---' Dockerfile; then
  # Insert debug RUN right before "RUN npm run build" in webbuild stage
  perl -0777 -pe 's/RUN npm run build/RUN echo \"--- Web stage tree ---\" \&\& ls -la \&\& echo \"--- src ---\" \&\& ls -la src \|\| true \&\& echo \"--- src\/lib ---\" \&\& ls -la src\/lib \|\| true \&\& echo \"--- App.tsx head ---\" \&\& head -n 20 src\/App.tsx \|\| true \n\nRUN npm run build/;' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Added debug listing before Vite build"
else
  echo "ℹ️  Dockerfile already has webbuild debug listing"
fi

# ---- Step 3: fix Gunicorn PORT expansion (CMD) ----
# Replace any existing CMD line with sh -c variant that expands ${PORT}
if grep -q '^CMD \["gunicorn' Dockerfile; then
  perl -0777 -pe 's#^CMD \[.*gunicorn[^\n]*\]\s*$#CMD ["sh","-c","gunicorn -k gevent -w ${WORKERS:-1} --access-logfile - --error-logfile - -t 0 -b 0.0.0.0:${PORT} app:app"]#m;' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Replaced exec-form CMD with sh -c (PORT expansion)"
elif grep -q '^CMD \["sh","-c"' Dockerfile; then
  # Update to enforce PORT usage
  perl -0777 -pe 's#^CMD \["sh","-c",.*\]\s*$#CMD ["sh","-c","gunicorn -k gevent -w ${WORKERS:-1} --access-logfile - --error-logfile - -t 0 -b 0.0.0.0:${PORT} app:app"]#m;' Dockerfile > Dockerfile.tmp && mv Dockerfile.tmp Dockerfile
  echo "✅ Updated sh -c CMD to bind 0.0.0.0:${PORT}"
else
  # Append if missing
  cat >> Dockerfile <<'DOCKER'
CMD ["sh","-c","gunicorn -k gevent -w ${WORKERS:-1} --access-logfile - --error-logfile - -t 0 -b 0.0.0.0:${PORT} app:app"]
DOCKER
  echo "✅ Added sh -c CMD for Gunicorn"
fi

# ---- Step 4: optional railway.toml (for monorepo explicit Dockerfile) ----
if [[ ! -f "railway.toml" ]]; then
  cat > railway.toml <<'TOML'
[build]
builder = "DOCKERFILE"
dockerfilePath = "./Dockerfile"
TOML
  echo "✅ Created railway.toml"
else
  echo "ℹ️  railway.toml already exists"
fi

# ---- Step 5: Git commit/push (optional remote auto-init) ----
if [[ -n "${GIT_REMOTE_URL}" ]]; then
  if [[ ! -d ".git" ]]; then
    git init
    git checkout -b main
  fi
  git add .
  git commit -m "chore: fix Vite lib/api.ts & Gunicorn PORT; add cache-bust/debug/railway.toml" || true
  if ! git remote | grep -q origin; then
    git remote add origin "${GIT_REMOTE_URL}"
  fi
  git push -u origin main
  echo "✅ Pushed to ${GIT_REMOTE_URL}"
else
  echo "ℹ️  GIT_REMOTE_URL not set; skipped push"
fi

# ---- Step 6: Railway deploy (optional) ----
if [[ -n "${RAILWAY_TOKEN}" ]]; then
  if ! command -v railway >/dev/null 2>&1; then
    npm i -g @railway/cli
  fi
  railway login --token "${RAILWAY_TOKEN}"
  railway up --service "${RAILWAY_SERVICE}"
  echo "🚀 Railway deploy triggered for service=${RAILWAY_SERVICE}"
else
  echo "ℹ️  RAILWAY_TOKEN not set; skipped railway up"
fi

# ---- Step 7: Health check (optional URL autodetect requires env) ----
APP_URL="${APP_URL:-}"
if [[ -n "${APP_URL}" ]]; then
  echo "⏳ Waiting 10s for app to come up..."
  sleep 10
  echo "➡️  GET ${APP_URL}${HEALTH_PATH}"
  curl -fsS "${APP_URL}${HEALTH_PATH}" || true
  echo -e "\n➡️  SSE test: ${APP_URL}/api/stream?question=${STREAM_TEST_Q} (showing first 3 events)"
  curl -N --max-time 10 "${APP_URL}/api/stream?question=${STREAM_TEST_Q}" | head -n 6 || true
fi

echo "✅ Done."
