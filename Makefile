.PHONY: build
build:
	@./scripts/build.sh

.PHONY: run
run:
	@cd dev_server && go run server.go --templateDir ../pages

.PHONY: deploy
deploy:
	@./scripts/deploy.sh ./dist