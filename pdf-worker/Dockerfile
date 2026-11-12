FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends ghostscript ca-certificates   && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY index.js ./
ENV NODE_ENV=production
ENV PORT=8080
CMD ["node", "index.js"]
