# syntax=docker/dockerfile:1

ARG GO_VERSION=1.26.1

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS builder
WORKDIR /src

ENV CGO_ENABLED=0 \
    GOEXPERIMENT=jsonv2

RUN apk add --no-cache ca-certificates git

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG TARGETOS
ARG TARGETARCH
ARG VERSION=TempVersion

RUN GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH:-amd64} \
    go build -v -trimpath \
    -ldflags "-X 'github.com/wyx2685/v2node/cmd.version=${VERSION}' -s -w -buildid=" \
    -o /out/v2node .

FROM alpine:3.22

RUN apk add --no-cache ca-certificates tzdata \
    && mkdir -p /etc/v2node

ENV TZ=Asia/Shanghai

COPY --from=builder /out/v2node /usr/local/bin/v2node
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/etc/v2node"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server"]
