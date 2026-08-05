# Hardened reverse proxy in front of nimbus-orders-api.
# Build from repo root: docker build -f docker/nginx/Dockerfile -t nimbus/nginx .
#
# Pin base image by digest in prod, e.g. nginx:1.27-alpine@sha256:<digest>
# Resolve with: docker buildx imagetools inspect nginx:1.27-alpine
#
# Runs as the non-root nginx user (uid 101). Master binds high ports (8080/8443)
# and writes pid + temp files under /tmp so the rootfs can be mounted read-only
# (mount a tmpfs at /tmp in that case).

FROM nginx:1.27-alpine

RUN rm -f /etc/nginx/conf.d/default.conf \
 && mkdir -p /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp \
 && chown -R nginx:nginx /tmp/client_temp /tmp/proxy_temp /tmp/fastcgi_temp /tmp/uwsgi_temp /tmp/scgi_temp /var/cache/nginx

COPY docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY docker/nginx/conf.d/nimbus.conf /etc/nginx/conf.d/nimbus.conf

EXPOSE 8080 8443

USER nginx

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
