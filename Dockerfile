# ==========================================
# 1. 编译阶段：针对目标平台构建 (支持 CGO，如 sqlite3)
# ==========================================
FROM golang:1.20-alpine AS build-env

RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk --no-cache add git gcc musl-dev

# 配置国内 Go 模块代理
ENV GOPROXY=https://goproxy.cn,direct

# 解决 musl 1.24+ (Alpine 3.18+) 缺少 LFS64 (pread64, off64_t) 定义导致 sqlite3 编译报错的问题
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE -D_GNU_SOURCE"

ENV D=/go/src/github.com/fnproject/fn
ADD . $D

# 使用项目自带的 -mod=vendor，保留 CGO (sqlite3 强依赖 CGO)
RUN cd $D/cmd/fnserver && \
    CGO_CFLAGS="-D_LARGEFILE64_SOURCE -D_GNU_SOURCE" go build -mod=vendor -ldflags "-s -w" -o /tmp/fn-alpine

# ==========================================
# 2. 运行阶段：使用官方支持 ARM64/AMD64 的 dind 基础镜像
# ==========================================
FROM docker:20.10-dind

RUN apk add --no-cache tzdata ca-certificates bash \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && addgroup -g 2999 docker 2>/dev/null || true

# 复制原 fnproject/dind 所需的预启动脚本
COPY images/dind/preentry.sh /usr/local/bin/preentry.sh
RUN chmod +x /usr/local/bin/preentry.sh

WORKDIR /app
COPY --from=build-env /tmp/fn-alpine /app/fnserver
RUN chmod +x /app/fnserver

ENTRYPOINT ["/usr/local/bin/preentry.sh"]
CMD ["./fnserver"]
EXPOSE 8080