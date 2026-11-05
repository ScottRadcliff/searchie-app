.DEFAULT_GOAL := help

COMPOSE ?= docker compose
SERVICE ?= app
SEARCH_PATH ?= sample.txt
QUERY ?= Lorem
# Preserve literal dollar signs instead of interpreting them as Make variables.
override SEARCH_PATH := $(value SEARCH_PATH)
override QUERY := $(value QUERY)
export SEARCH_PATH QUERY

.PHONY: help build up down stop restart logs ps shell console test format check search package

help:
	@echo 'build    Build the development image'
	@echo 'up       Start the development container with attached logs'
	@echo 'down     Remove containers and networks; retain volumes'
	@echo 'stop     Stop containers'
	@echo 'restart  Restart containers'
	@echo 'logs     Follow container logs'
	@echo 'ps       Show service status'
	@echo 'shell    Open a shell (requires make up in another terminal)'
	@echo 'console  Open IEx with Searchie loaded (requires make up)'
	@echo 'test     Run tests in a temporary container'
	@echo 'format   Format Elixir source in a temporary container'
	@echo 'check    Check formatting and run tests'
	@echo 'search   Search files: make search SEARCH_PATH=sample.txt QUERY=Lorem'
	@echo 'package  Build the standalone ./searchie escript'

build:
	$(COMPOSE) build $(SERVICE)

up:
	$(COMPOSE) up $(SERVICE)

down:
	$(COMPOSE) down

stop:
	$(COMPOSE) stop $(SERVICE)

restart:
	$(COMPOSE) restart $(SERVICE)

logs:
	$(COMPOSE) logs --follow $(SERVICE)

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec $(SERVICE) sh

console:
	$(COMPOSE) exec $(SERVICE) iex -S mix

test:
	$(COMPOSE) run --rm -T $(SERVICE) mix test

format:
	$(COMPOSE) run --rm -T $(SERVICE) mix format

check:
	$(COMPOSE) run --rm -T $(SERVICE) sh -c 'mix format --check-formatted && mix test'

package:
	$(COMPOSE) run --rm -T $(SERVICE) mix escript.build

# Pass search arguments as environment values, not interpolated shell code.
search:
	$(COMPOSE) run --rm -T -e SEARCH_PATH -e QUERY $(SERVICE) sh -c 'exec mix filter "$$SEARCH_PATH" "$$QUERY"'
