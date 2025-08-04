.PHONY: build
build:
	@./scripts/build.sh

.PHONY: run
run:
	@cd dev_server && go run server.go --templateDir ../pages