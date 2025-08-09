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
# 覆盖前端产物
COPY --from=frontend /app/web/dist ./web/dist

# 多架构编译
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH go build -ldflags="-s -w" -o /out/memos ./bin/memos

# ---------- 3) Runtime ----------
# 用 distroless 带CA证书的精简镜像；非root运行
FROM gcr.io/distroless/base-debian12:nonroot
WORKDIR /var/opt/memos
COPY --from=backend /out/memos /usr/local/bin/memos
EXPOSE 5230
VOLUME ["/var/opt/memos"]
ENTRYPOINT ["/usr/local/bin/memos"]
