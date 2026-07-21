FROM node:20-alpine

WORKDIR /app

# Copy package files first (layer caching — only reinstalls if package.json changes)
COPY package*.json ./
RUN npm install --omit=dev

# Copy source code
COPY src/ ./src/

EXPOSE 3000

CMD ["node", "src/index.js"]
