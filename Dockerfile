# build stage
FROM golang:1.10-alpine AS build-env
#RUN apk --no-cache add build-base git bzr mercurial gcc
RUN sed -i 's/dl-cdn.alpinelinux.org/mirrors.tuna.tsinghua.edu.cn/g' /etc/apk/repositories \
    && apk --no-cache add build-base git bzr mercurial gcc
ENV D=/go/src/github.com/fnproject/fn
ADD . $D
RUN cd $D/cmd/fnserver && go build -o fn-alpine && cp fn-alpine /tmp/

# final stage: the local fnproject/dind:latest will be either built afresh or
# whatever is the latest from master, depending on whether we're releasing
# a newer cut.
FROM fnproject/dind:17.12.0-ce

RUN apk add --no-cache tzdata \
    && cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone

WORKDIR /app
COPY --from=build-env /tmp/fn-alpine /app/fnserver
CMD ["./fnserver"]
EXPOSE 8080
