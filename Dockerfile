# ---------- 1) Build frontend ----------
FROM node:22-bookworm AS frontend
WORKDIR /app/web
# 只拷依赖清单，先装依赖以利用缓存
COPY web/pnpm-lock.yaml web/package.json ./
# 使用 corepack 管理 pnpm；锁定一个稳定版，避免CI环境差异
RUN corepack enable && corepack prepare pnpm@8.15.4 --activate
RUN pnpm install --frozen-lockfile
# 拷其余前端源码并构建
COPY web/. .
RUN pnpm build   # 产物在 /app/web/dist

# ---------- 2) Build backend ----------
FROM golang:1.23-bookworm AS backend
WORKDIR /src
# 先下依赖
COPY go.mod go.sum ./
RUN go mod download
# 拷全部后端源码
COPY . .
# 覆盖前端产物（给 go:embed 用）
COPY --from=frontend /app/web/dist ./web/dist
# 适配多架构构建（buildx 会注入这两个 ARG）
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0
# -s -w 压缩符号表；适配不同架构
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" -o /out/memos ./bin/memos

# ---------- 3) Runtime ----------
# 用 distroless 带CA证书的精简镜像；非root运行
FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /var/opt/memos
COPY --from=backend /out/memos /usr/local/bin/memos
EXPOSE 5230
VOLUME ["/var/opt/memos"]
ENTRYPOINT ["/usr/local/bin/memos"]
