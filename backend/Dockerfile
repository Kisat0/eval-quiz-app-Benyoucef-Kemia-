FROM node:22.23.1-alpine3.23
ENV NODE_ENV=production
RUN apk upgrade --no-cache
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
    /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack \
    /opt/yarn-v1.22.22 /usr/local/bin/yarn /usr/local/bin/yarnpkg
COPY server.js ./
USER node
EXPOSE 3007
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s CMD wget -qO- http://127.0.0.1:3007/health >/dev/null || exit 1
CMD ["node", "server.js"]