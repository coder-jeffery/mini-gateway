FROM openresty/openresty:alpine-fat

RUN apk add --no-cache sqlite-libs sqlite-dev gcc musl-dev make \
    && luarocks install lsqlite3 \
    && apk del gcc musl-dev make sqlite-dev
