# ===========================
# DOMjudge Docker Deployment
# ===========================

ENV ?= dev
ENV_FILE := .env.$(ENV)

ifeq ($(ENV),prod)
COMPOSE_FILE := -f docker-compose.dev.yml -f docker-compose.yml
else
COMPOSE_FILE := -f docker-compose.dev.yml
endif

DC := docker compose

ifeq (,$(wildcard $(ENV_FILE)))
$(error Environment file '$(ENV_FILE)' not found!)
endif

.PHONY: setup lifecycle debug scaling misc help

# ===========================
# Setup
# ===========================
init-dev:
	@test -f .env.dev || cp .env.dev.example .env.dev
	@echo "✅ .env.dev created from template"

init-prod:
	@test -f .env.prod || cp .env.prod.example .env.prod
	@echo "✅ .env.prod created from template"

setup-host:
	@echo "🔍 Checking host prerequisites..."
	@bash scripts/domjudge_host_setup.sh run_all_checks --fix || { echo >&2 "❌ Host setup failed."; exit 1; }

hash-password:
	@bash scripts/hash_traefik_password.sh $(ENV_FILE)

extract-judgehost-password:
	@bash scripts/extract_judgehost_password.sh $(ENV)

# ===========================
# Lifecycle
# ===========================

up: setup-host
	@echo "🚀 Starting services for $(ENV)..."
	$(DC) --env-file $(ENV_FILE) $(COMPOSE_FILE) up -d
	@echo "\nℹ️  To get judgehost password: make extract-judgehost-password ENV=$(ENV)"

down:
	@echo "🛑 Stopping services for $(ENV)..."
	$(DC) --env-file $(ENV_FILE) $(COMPOSE_FILE) down

restart:
	@echo "🔄 Restarting services for $(ENV)..."
	$(DC) --env-file $(ENV_FILE) $(COMPOSE_FILE) restart

# ===========================
# Debugging
# ===========================

logs:
	@echo "📜 Showing logs for $(ENV)..."
	$(DC) --env-file $(ENV_FILE) $(COMPOSE_FILE) logs -f

ps:
	@echo "📋 Listing containers for $(ENV)..."
	$(DC) --env-file $(ENV_FILE) $(COMPOSE_FILE) ps

env:
	@echo "🌍 Using environment: $(ENV)"
	@cat $(ENV_FILE)

# ===========================
# Scaling
# ===========================

scale:
	@if [ -z "$(N)" ]; then \
		echo "Usage: make scale ENV=prod N=5"; \
		exit 1; \
	fi
	@echo "⚖️  Scaling judgehost to $(N) replicas for $(ENV)..."
	$(DC) --env-file $(ENV_FILE) $(COMPOSE_FILE) up -d --scale judgehost=$(N)

# ===========================
# Help
# ===========================

help:
	@echo "📖 Available targets:"
	@echo ""
	@echo "Setup:"
	@echo "  setup-host              - Verify & install host prerequisites"
	@echo "  hash-password           - Generate TRAEFIK_HASHED_PASSWORD from plaintext"
	@echo "  extract-judgehost-password - Extract JUDGEHOST_PASSWORD from domserver logs"
	@echo ""
	@echo "Lifecycle:"
	@echo "  up       - Start services (default: dev, override with ENV=prod)"
	@echo "  down     - Stop services"
	@echo "  restart  - Restart services"
	@echo ""
	@echo "Debugging:"
	@echo "  logs     - Show container logs"
	@echo "  ps       - List running containers"
	@echo "  env      - Show active environment file"
	@echo ""
	@echo "Scaling:"
	@echo "  scale    - Scale judgehost service (Usage: make scale ENV=prod N=5)"
	@echo ""
	@echo "Examples:"
	@echo "  make up ENV=prod"
	@echo "  make scale ENV=prod N=3"
	@echo "  make logs ENV=dev"
