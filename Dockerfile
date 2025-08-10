# ---------- 1) Build frontend ----------
FROM node:22-alpine AS web
WORKDIR /src/web
COPY web/pnpm-lock.yaml web/package.json ./
RUN corepack enable && pnpm install --frozen-lockfile
COPY web/. .
RUN pnpm build  # 产物在 /src/web/dist

# ---------- 2) Build backend ----------
FROM golang:1.24-bookworm AS backend
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download -x
COPY . .

# ✅ 把前端产物放到 go:embed 期望的目录
COPY --from=frontend /app/web/dist ./server/router/frontend/dist
# （可选）构建期断言，防止空包
RUN test -f ./server/router/frontend/dist/index.html && echo "frontend embedded OK"

# ✅ 编译时加 embed 标签
ARG TARGETOS TARGETARCH
ENV CGO_ENABLED=0
RUN GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -tags=embed -ldflags="-s -w" -o /out/memos ./bin/memos/main.go

# ---------- 3) Runtime ----------
FROM gcr.io/distroless/base-debian12
WORKDIR /var/opt/memos
COPY --from=build /out/memos /usr/local/bin/memos
EXPOSE 5230
VOLUME ["/var/opt/memos"]
ENTRYPOINT ["/usr/local/bin/memos"]
