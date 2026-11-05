# Optional gateway-only image (no Admin UI). Default compose build uses repo root Dockerfile.
FROM openresty/openresty:alpine-fat

RUN apk add --no-cache sqlite-libs sqlite-dev gcc musl-dev make \
    && luarocks install lsqlite3 \
    && apk del gcc musl-dev make sqlite-dev
