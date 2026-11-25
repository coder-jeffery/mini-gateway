FROM node:20-alpine AS builder

WORKDIR /app
ENV NEXT_TELEMETRY_DISABLED=1
# Next.js production build can spike memory on Docker Desktop defaults.
ENV NODE_OPTIONS=--max-old-space-size=2048
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-alpine AS runner

WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
# Runtime GATEWAY_ADMIN_URL is set by docker-compose (Docker DNS: openresty).
ENV GATEWAY_ADMIN_URL=http://openresty:8080/admin/gw/v1
ENV GATEWAY_ADMIN_SECRET=admin-secret-2026

COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static
COPY --from=builder /app/public ./public

EXPOSE 3000

CMD ["node", "server.js"]
