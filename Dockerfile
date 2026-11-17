FROM node:22.23.1-alpine3.23 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginxinc/nginx-unprivileged:1.30.6-alpine
USER root
RUN apk upgrade --no-cache
ENV BACKEND_SCHEME=http \
    BACKEND_HOST=backend \
    BACKEND_PORT=3007 \
    NGINX_ENVSUBST_FILTER=BACKEND_
COPY nginx/default.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
USER nginx
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget -qO- http://127.0.0.1:8080/ >/dev/null || exit 1