# mini-gateway (OpenResty only)
FROM openresty/openresty:alpine-fat

RUN apk add --no-cache sqlite-libs sqlite-dev gcc musl-dev make \
    && luarocks install lsqlite3 \
    && apk del gcc musl-dev make sqlite-dev

COPY nginx/conf/nginx.conf /usr/local/openresty/nginx/conf/nginx.conf
COPY nginx/lua /usr/local/openresty/nginx/lua

COPY docker/entrypoint-gateway.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
