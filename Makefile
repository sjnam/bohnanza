# 보난자 문학적 프로그램 빌드용 Makefile.
#
#   make          # tangle + 문서 조판
#   make tangle   # .w -> .go
#   make doc      # PDF 조판 (한글이라 luatex)
#   make test     # go test ./...
#   make arena    # 봇 실력 측정 (go test -v ./bot)
#   make cli      # CLI 실행 (예: make cli ARGS="3 1 42")
#   make serve    # 서버 실행 (예: make serve ARGS=":8080")
#   make clean    # 생성물 삭제 (.w 원본은 남김)

GTANGLE ?= gtangle
GWEAVE  ?= gweave

.PHONY: all tangle doc test arena cli server clean
.DEFAULT_GOAL := all

all: tangle doc

tangle: engine/bohnanza.go cli/cli.go server/server.go bot/bot.go

engine/bohnanza.go: engine/bohnanza.w
	$(GTANGLE) engine/bohnanza.w

cli/cli.go: cli/cli.w
	$(GTANGLE) cli/cli.w

server/server.go: server/server.w
	$(GTANGLE) server/server.w

bot/bot.go: bot/bot.w
	$(GTANGLE) bot/bot.w

doc: engine/bohnanza.pdf cli/cli.pdf server/server.pdf bot/bot.pdf

engine/bohnanza.pdf: engine/bohnanza.w
	cd engine && $(GWEAVE) bohnanza.w && luatex bohnanza.tex </dev/null

cli/cli.pdf: cli/cli.w
	cd cli && $(GWEAVE) cli.w && luatex cli.tex </dev/null

server/server.pdf: server/server.w
	cd server && $(GWEAVE) server.w && luatex server.tex </dev/null

bot/bot.pdf: bot/bot.w
	cd bot && $(GWEAVE) bot.w && luatex bot.tex </dev/null

test: tangle
	go test ./...

arena: tangle
	go test -v ./bot

cli: tangle
	go run ./cli $(ARGS)

server: tangle
	go run ./server $(ARGS)

clean:
	rm -f engine/bohnanza.tex engine/bohnanza.log engine/bohnanza.toc engine/bohnanza.pdf
	rm -f cli/cli.tex cli/cli.log cli/cli.toc cli/cli.pdf
	rm -f server/server.tex server/server.log server/server.toc server/server.pdf
	rm -f bot/bot.tex bot/bot.log bot/bot.toc bot/bot.pdf
