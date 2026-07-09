# Homelab Docker Compose helpers
# Usage: make help | make up | make down | make up-peryite | make down-sanguine | ...

COMPOSE := docker compose

HORMAEUS  := src/Hormaeus Mora
NOCTURNAL := src/Nocturnal
PERYITE   := src/Peryite
SANGUINE  := src/Sanguine
SHEOGORATH := src/Sheogorath/mcp/public

# Stacks included in make up / make down.
# Sheogorath is omitted until its docker-compose.yml is non-empty.
STACKS := hormaeus nocturnal peryite sanguine

.DEFAULT_GOAL := help

.PHONY: help up down \
	up-hormaeus down-hormaeus \
	up-nocturnal down-nocturnal \
	up-peryite down-peryite \
	up-sanguine down-sanguine \
	up-sheogorath down-sheogorath \
	ps

help:
	@echo "Homelab compose targets"
	@echo ""
	@echo "  make up / make down     all stacks: $(STACKS)"
	@echo "  make up-<stack>         start one stack"
	@echo "  make down-<stack>       stop one stack"
	@echo "  make ps                 show compose project status"
	@echo ""
	@echo "Stacks: hormaeus nocturnal peryite sanguine sheogorath"

# --- all ---

up: up-hormaeus up-nocturnal up-peryite up-sanguine

down: down-sanguine down-peryite down-nocturnal down-hormaeus

# --- Hormaeus Mora (Nextcloud + MariaDB + metrics) ---

up-hormaeus:
	$(COMPOSE) -f "$(HORMAEUS)/docker-compose.yml" --project-directory "$(HORMAEUS)" up -d --build

down-hormaeus:
	$(COMPOSE) -f "$(HORMAEUS)/docker-compose.yml" --project-directory "$(HORMAEUS)" down

# --- Nocturnal (Nginx Proxy Manager) ---

up-nocturnal:
	$(COMPOSE) -f "$(NOCTURNAL)/docker-compose.yml" --project-directory "$(NOCTURNAL)" up -d

down-nocturnal:
	$(COMPOSE) -f "$(NOCTURNAL)/docker-compose.yml" --project-directory "$(NOCTURNAL)" down

# --- Peryite (Pi-hole) ---

up-peryite:
	$(COMPOSE) -f "$(PERYITE)/docker-compose.yml" --project-directory "$(PERYITE)" up -d

down-peryite:
	$(COMPOSE) -f "$(PERYITE)/docker-compose.yml" --project-directory "$(PERYITE)" down

# --- Sanguine (Jellyfin) ---
# Requires external network homelab_default and a real media path in compose.

up-sanguine:
	$(COMPOSE) -f "$(SANGUINE)/docker-compose.yml" --project-directory "$(SANGUINE)" up -d

down-sanguine:
	$(COMPOSE) -f "$(SANGUINE)/docker-compose.yml" --project-directory "$(SANGUINE)" down

# --- Sheogorath (MCP public) ---
# Compose file is currently empty; targets exist for when it is filled in.

up-sheogorath:
	$(COMPOSE) -f "$(SHEOGORATH)/docker-compose.yml" --project-directory "$(SHEOGORATH)" up -d

down-sheogorath:
	$(COMPOSE) -f "$(SHEOGORATH)/docker-compose.yml" --project-directory "$(SHEOGORATH)" down

# --- status ---

ps:
	@$(COMPOSE) ls -a
