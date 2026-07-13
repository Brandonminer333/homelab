# Homelab Docker Compose helpers
# Usage: make help | make up | make down | make up-peryite | make down-sanguine | ...

COMPOSE := docker compose

HORMAEUS   := src/Hormaeus Mora
PERYITE    := src/Peryite
SANGUINE   := src/Sanguine
CLAVICUS   := src/Clavicus Vile
NOCTURNAL  := src/Nocturnal
SHEOGORATH := src/Sheogorath/mcp/public

# Stacks included in make up / make down.
# Sheogorath is omitted until its docker-compose.yml is non-empty.
# Nocturnal (nginx) is last on up so upstreams are resolvable at start.
STACKS := hormaeus peryite sanguine clavicus nocturnal

.DEFAULT_GOAL := help

.PHONY: help up down \
	up-hormaeus down-hormaeus \
	up-peryite down-peryite \
	up-sanguine down-sanguine \
	up-clavicus down-clavicus \
	up-nocturnal down-nocturnal \
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
	@echo "Stacks: hormaeus peryite sanguine clavicus nocturnal sheogorath"

# --- all ---
# Apps first, then nginx. Tear down nginx first so it is not left pointing at
# stopped upstreams.

up: up-hormaeus up-peryite up-sanguine up-clavicus up-nocturnal

down: down-nocturnal down-clavicus down-sanguine down-peryite down-hormaeus

# --- Hormaeus Mora (Nextcloud + MariaDB + metrics) ---

up-hormaeus:
	$(COMPOSE) -f "$(HORMAEUS)/docker-compose.yml" --project-directory "$(HORMAEUS)" up -d --build

down-hormaeus:
	$(COMPOSE) -f "$(HORMAEUS)/docker-compose.yml" --project-directory "$(HORMAEUS)" down

# --- Peryite (Pi-hole) ---

up-peryite:
	$(COMPOSE) -f "$(PERYITE)/docker-compose.yml" --project-directory "$(PERYITE)" up -d

down-peryite:
	$(COMPOSE) -f "$(PERYITE)/docker-compose.yml" --project-directory "$(PERYITE)" down

# --- Sanguine (Jellyfin) ---
# Reached via Nocturnal at /jellyfin; set a real media path in compose.

up-sanguine:
	$(COMPOSE) -f "$(SANGUINE)/docker-compose.yml" --project-directory "$(SANGUINE)" up -d

down-sanguine:
	$(COMPOSE) -f "$(SANGUINE)/docker-compose.yml" --project-directory "$(SANGUINE)" down

# --- Clavicus Vile (qBittorrent + Proton VPN via Gluetun) ---
# Isolated from Oblivion; WebUI on 127.0.0.1:8085 (SSH forward).
# Requires WIREGUARD_PRIVATE_KEY in src/Clavicus Vile/.env

up-clavicus:
	$(COMPOSE) -f "$(CLAVICUS)/docker-compose.yml" --project-directory "$(CLAVICUS)" up -d

down-clavicus:
	$(COMPOSE) -f "$(CLAVICUS)/docker-compose.yml" --project-directory "$(CLAVICUS)" down

# --- Nocturnal (nginx reverse proxy) ---
# Path-based TLS proxy on Oblivion. Start after app stacks.

up-nocturnal:
	$(COMPOSE) -f "$(NOCTURNAL)/docker-compose.yml" --project-directory "$(NOCTURNAL)" up -d

down-nocturnal:
	$(COMPOSE) -f "$(NOCTURNAL)/docker-compose.yml" --project-directory "$(NOCTURNAL)" down

# --- Sheogorath (MCP public) ---
# Compose file is currently empty; targets exist for when it is filled in.

up-sheogorath:
	$(COMPOSE) -f "$(SHEOGORATH)/docker-compose.yml" --project-directory "$(SHEOGORATH)" up -d

down-sheogorath:
	$(COMPOSE) -f "$(SHEOGORATH)/docker-compose.yml" --project-directory "$(SHEOGORATH)" down

# --- status ---

ps:
	@$(COMPOSE) ls -a
