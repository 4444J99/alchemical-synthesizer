# Brahma Foundry — productization service
FROM node:24-alpine

WORKDIR /app
COPY package.json package-lock.json ./
# Install only production deps; 'stripe' is optional and pulled in if present.
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund

COPY . .

ENV PORT=4000 \
    FOUNDRY_DATA_DIR=/data
VOLUME ["/data"]
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=4s --start-period=5s \
  CMD wget -qO- http://localhost:4000/healthz || exit 1

CMD ["node", "server.js"]
