# 보난자 문학적 프로그램 빌드용 Makefile.
#
#   make          # tangle + 문서 조판
#   make tangle   # .w -> .go
#   make doc      # PDF 조판 (한글이라 luatex)
#   make test     # go test ./...
#   make arena    # 봇 실력 측정 (go test -v ./ai)
#   make cli      # CLI 실행 (예: make cli ARGS="3 1 42")
#   make serve    # 서버 실행 (예: make serve ARGS=":8080")
#   make clean    # 생성물 삭제 (.w 원본은 남김)

GTANGLE ?= gtangle
GWEAVE  ?= gweave

.PHONY: all tangle doc test arena cli server clean
.DEFAULT_GOAL := all

all: tangle doc

tangle: engine/engine.go cli/cli.go server/server.go ai/ai.go

engine/engine.go: engine/engine.w
	$(GTANGLE) engine/engine.w

cli/cli.go: cli/cli.w
	$(GTANGLE) cli/cli.w

server/server.go: server/server.w
	$(GTANGLE) server/server.w

ai/ai.go: ai/ai.w
	$(GTANGLE) ai/ai.w

doc: engine/engine.pdf cli/cli.pdf server/server.pdf ai/ai.pdf

engine/engine.pdf: engine/engine.w
	cd engine && $(GWEAVE) engine.w && luatex engine.tex </dev/null

cli/cli.pdf: cli/cli.w
	cd cli && $(GWEAVE) cli.w && luatex cli.tex </dev/null

server/server.pdf: server/server.w
	cd server && $(GWEAVE) server.w && luatex server.tex </dev/null

ai/ai.pdf: ai/ai.w
	cd ai && $(GWEAVE) ai.w && luatex ai.tex </dev/null

test: tangle
	go test ./...

arena: tangle
	go test -v ./ai

cli: tangle
	go run ./cli $(ARGS)

server: tangle
	go run ./server $(ARGS)

clean:
	rm -f engine/*.go engine/engine.tex engine/engine.log engine/engine.toc engine/engine.pdf
	rm -f cli/*.go cli/cli.tex cli/cli.log cli/cli.toc cli/cli.pdf
	rm -f server/*.go server/server.tex server/server.log server/server.toc server/server.pdf
	rm -f ai/*.go ai/ai.tex ai/ai.log ai/ai.toc ai/ai.pdf
