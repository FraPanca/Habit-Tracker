# Stage 1: build
FROM node:20.18-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .

# Stage 2: test
FROM build AS test
RUN npm run test

# Stage 3: production
FROM node:20.18-alpine AS production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 5000
USER node
CMD ["npm", "start"]