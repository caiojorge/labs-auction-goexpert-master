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

.PHONY: test e2e

test:
	@echo "Running unit tests"
	go test ./...

e2e:
	@echo "Running end-to-end tests (requires Docker)"
	AUCTION_DURATION=3s $(DC) up --build -d
	RUN_BID_FLOW=1 SLEEP_AUTO_CLOSE=4 ./scripts/test_endpoints.sh || { $(DC) logs app --tail=200; $(DC) down; exit 1; }
	$(DC) down
