.PHONY: build
build:
	@./scripts/build.sh

.PHONY: run
run:
	@cd dev_server && go run server.go --templateDir ../pages

.PHONY: test
test: build
	@cd dev_server && go test ./...
	@python3 ./scripts/check_dist.py

.PHONY: deploy
deploy: test
	@./scripts/deploy.sh ./dist