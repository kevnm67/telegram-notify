# telegram-notify orb — developer entry points. `make help` lists targets.
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ORB_NAME ?= kevnm67/telegram-notify
PACKED   ?= orb.yml
DOCKER_IMAGE ?= cimg/base:current-22.04
D2_FLAGS := --theme 0 --scale 2 --pad 60
DIAGRAM_SRCS := $(wildcard docs/architecture/*.d2)
DIAGRAM_SVGS := $(DIAGRAM_SRCS:.d2=.svg)
DIAGRAM_PNGS := $(DIAGRAM_SRCS:.d2=.png)

.PHONY: help setup lint test test-bash32 integration coverage build validate review pack publish-dev generate-commands diagrams verify-diagrams wiki-sync clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

setup: ## Install local tooling (brew) and pre-commit hooks
	brew list bats-core >/dev/null 2>&1 || brew install bats-core
	brew list shellcheck >/dev/null 2>&1 || brew install shellcheck
	brew list circleci >/dev/null 2>&1 || brew install circleci
	brew list d2 >/dev/null 2>&1 || brew install d2
	command -v pre-commit >/dev/null || pip install pre-commit
	pre-commit install

lint: ## shellcheck + yamllint + markdownlint + orb validate
	shellcheck -x src/scripts/*.sh scripts/ci/*.sh tests/test_helper/mock_bin/curl
	yamllint --strict .
	@command -v markdownlint >/dev/null && markdownlint --config .markdownlint.yaml '**/*.md' --ignore node_modules || echo "markdownlint not installed — skipped"
	$(MAKE) validate

test: ## Run the bats unit suite
	./scripts/ci/run-unit-tests.sh

test-bash32: ## Run the bats suite on bash 3.2 without jq/python3 (Docker)
	docker run --rm --platform linux/amd64 -v "$(CURDIR)":/repo -w /repo bash:3.2 \
		bash -c './scripts/ci/install-test-tools.sh --minimal >/dev/null && ./scripts/ci/run-unit-tests.sh'

integration: ## Run every template against the mock Telegram + stubbed CircleCI/Anthropic APIs
	./scripts/ci/run-integration-locally.sh

generate-commands: ## Regenerate src/commands/*.yml from scripts/dev/generate-commands.py
	python3 scripts/dev/generate-commands.py

coverage: ## Run unit tests under kcov (Linux); on macOS runs inside Docker
ifeq ($(shell uname -s),Linux)
	./scripts/ci/run-unit-tests.sh --coverage
else
	docker run --rm --platform linux/amd64 -v "$(CURDIR)":/repo -w /repo $(DOCKER_IMAGE) \
		bash -c './scripts/ci/install-test-tools.sh >/dev/null && ./scripts/ci/run-unit-tests.sh --coverage'
endif

pack: ## Pack src/ into a single orb.yml
	circleci orb pack src > $(PACKED)

validate: pack ## Pack and validate the orb
	circleci orb validate $(PACKED)

build: validate ## Alias for validate (pack + validate)

review: pack ## Run orb-tools style review locally (requires circleci CLI >= 0.1.2)
	circleci orb review $(PACKED) 2>/dev/null || echo "orb review runs in CI (orb-tools/review)"

publish-dev: validate ## Publish a dev version: make publish-dev TAG=alpha
	circleci orb publish $(PACKED) $(ORB_NAME)@dev:$(or $(TAG),alpha)

diagrams: $(DIAGRAM_SVGS) $(DIAGRAM_PNGS) ## Render docs/architecture/*.d2 to SVG + PNG

docs/architecture/%.svg: docs/architecture/%.d2
	d2 $(D2_FLAGS) $< $@

docs/architecture/%.png: docs/architecture/%.d2
	d2 $(D2_FLAGS) $< $@

verify-diagrams: ## Fail if rendered diagrams are stale or docs contain text diagrams
	D2_FLAGS="$(D2_FLAGS)" ./scripts/ci/verify-diagrams.sh

wiki-sync: diagrams ## Push wiki/*.md and rendered diagrams to the GitHub wiki
	./scripts/ci/sync-wiki.sh

clean: ## Remove generated files
	rm -rf coverage test-results $(PACKED) .wiki-tmp
