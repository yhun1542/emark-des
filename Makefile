.PHONY: setup build ui-build run dev docker-build

setup:
	python -m venv .venv && . .venv/bin/activate && pip install -r server/requirements.txt

ui-build:
	cd app && npm i && npm run build

build: ui-build
	mkdir -p server/static && cp -r app/dist/* server/static/ || true

run:
	cd server && FLASK_DEBUG=1 python app.py

docker-build:
	docker build -t emark-des:latest .

