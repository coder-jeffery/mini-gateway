#!/bin/sh
set -eu
/usr/local/openresty/bin/openresty -t
exec /usr/local/openresty/bin/openresty -g "daemon off;"
