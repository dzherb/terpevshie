.PHONY: build
build:
	@./scripts/build.sh

.PHONY: run
run:
	@uv run scripts/dev_server.py