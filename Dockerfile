# ---------- 1) Build frontend ----------
FROM node:22-bookworm AS web
WORKDIR /app/web
COPY web/pnpm-lock.yaml web/package.json ./
RUN corepack enable
RUN pnpm --version
RUN pnpm install --frozen-lockfile
COPY web/. .
RUN pnpm build    # => /app/web/dist

# ---------- 2) Build backend (name it "build") ----------
FROM golang:1.24-bookworm AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download -x
COPY . .
# ✅ 放到 go:embed 期望目录
COPY --from=web /app/web/dist ./server/router/frontend/dist
RUN test -f ./server/router/frontend/dist/index.html && echo "frontend embedded OK"

# ✅ 编译时加 embed 标签
ARG TARGETOS TARGETARCH
ENV CGO_ENABLED=0
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -tags=embed -ldflags="-s -w" -o /out/memos ./bin/memos

# ---------- 3) Runtime ----------
FROM debian:bookworm-slim
WORKDIR /var/opt/memos
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/memos /usr/local/bin/memos
EXPOSE 5230
VOLUME ["/var/opt/memos"]
ENTRYPOINT ["/usr/local/bin/memos"]
