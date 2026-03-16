.PHONY: help up down restart stop build logs ps

DC = docker compose

help:
	@echo "Comandos disponíveis:"
	@echo "  make up       - sobe os containers em background com build"
	@echo "  make down     - derruba os containers e rede"
	@echo "  make restart  - reinicia a stack"
	@echo "  make stop     - para os containers sem remover"
	@echo "  make build    - faz build das imagens"
	@echo "  make logs     - mostra logs da aplicação"
	@echo "  make ps       - lista status dos containers"

up:
	$(DC) up --build -d

down:
	$(DC) down

restart: down up

stop:
	$(DC) stop

build:
	$(DC) build

logs:
	$(DC) logs -f app

ps:
	$(DC) ps
