# 보난자 게임 서버 이미지.
# tangle된 Go 소스(bohnanza.go, bot/bot.go, server/server.go 등)를 그대로
# 빌드하므로 이미지 안에서 gtangle이 필요 없다. .w를 고쳤다면 호스트에서
# `make tangle`로 .go를 갱신한 뒤 다시 빌드한다.

FROM golang:1.26-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
# 정적 바이너리(CGO 없음). 웹 UI는 //go:embed로 바이너리에 박히지만,
# 실제 서비스에서는 nginx가 정적 파일을 대신 낸다.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -o /bin/bohnanza-server ./server

FROM alpine:3.20
RUN adduser -D -H bohnanza
USER bohnanza
COPY --from=build /bin/bohnanza-server /usr/local/bin/bohnanza-server
EXPOSE 8080
ENTRYPOINT ["bohnanza-server", ":8080"]
