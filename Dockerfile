# ---------- 1) Build frontend ----------
FROM node:22-bookworm AS frontend
WORKDIR /app/web
# 只拷依赖清单，先装依赖以利用缓存
COPY web/pnpm-lock.yaml web/package.json ./
# 让 Corepack 使用 package.json 指定的 pnpm 版本（不要手动 prepare 8.x）
RUN corepack enable
RUN pnpm --version
# 安装依赖
RUN pnpm install --frozen-lockfile
# 拷其余前端源码并构建
COPY web/. .
RUN pnpm build   # 产物在 /app/web/dist

# ---------- 2) Build backend ----------
FROM golang:1.24-bookworm AS backend
WORKDIR /src

# 先下依赖（开详细日志 & 设代理，失败能看清卡在哪个模块）
COPY go.mod go.sum ./
RUN go env -w GOPROXY=https://proxy.golang.org,direct \
    && go env -w GONOSUMDB="*" \
    && go mod download -x

# 拷全部源码
COPY . .
# 覆盖前端产物（给 go:embed 用，目标是 server/frontend/dist）
COPY --from=frontend /app/web/dist ./server/frontend/dist
# 可选：构建期校验，避免再次空包
RUN test -f ./server/frontend/dist/index.html && echo "frontend embedded OK"

# 多架构编译
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" -o /out/memos ./bin/memos

# ---------- 3) Runtime (debug-friendly) ----------
FROM debian:bookworm-slim
WORKDIR /var/opt/memos
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY --from=backend /out/memos /usr/local/bin/memos
EXPOSE 5230
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s CMD curl -fsS http://127.0.0.1:5230/api/ping || exit 1
VOLUME ["/var/opt/memos"]
ENTRYPOINT ["/usr/local/bin/memos"]

