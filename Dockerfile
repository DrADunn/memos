# ---------- 1) Build frontend ----------
FROM node:22-alpine AS web
WORKDIR /src/web
COPY web/pnpm-lock.yaml web/package.json ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY web/. .
RUN pnpm build  # 产物在 /src/web/dist

# ---------- 2) Build backend ----------
FROM golang:1.24-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# 把前端产物放到 Go 代码期望的目录，供 go:embed 收集
RUN mkdir -p server/frontend/dist
COPY --from=web /src/web/dist ./server/frontend/dist

# 用官方推荐的入口编译（注意带 main.go）
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go build -ldflags="-s -w" -o /out/memos ./bin/memos/main.go

# ---------- 3) Runtime ----------
FROM gcr.io/distroless/base-debian12
WORKDIR /var/opt/memos
COPY --from=build /out/memos /usr/local/bin/memos
EXPOSE 5230
VOLUME ["/var/opt/memos"]
ENTRYPOINT ["/usr/local/bin/memos"]
