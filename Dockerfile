# 1) Build frontend
FROM node:18-alpine AS webbuild
WORKDIR /web
COPY app/package.json app/package-lock.json* app/pnpm-lock.yaml* ./
RUN npm i --no-audit --no-fund
COPY app/src ./src
COPY app/index.html app/vite.config.ts app/tailwind.config.js ./
RUN npm run build

# 2) Python runtime
FROM python:3.11-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY server/requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY server/ ./ 
# copy built frontend into Flask static
COPY --from=webbuild /web/dist ./static
ENV PORT=8000
CMD ["gunicorn", "-k", "gevent", "-w", "1", "-t", "0", "-b", "0.0.0.0:${PORT}", "app:app"]
