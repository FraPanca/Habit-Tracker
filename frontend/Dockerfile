# Stage 1: deps
FROM node:20.19-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
RUN npm ci

# Stage 2: build
FROM deps AS build
COPY frontend ./frontend
WORKDIR /app/frontend
RUN npm run build

# Stage 3: test
FROM deps AS test
COPY frontend ./frontend
WORKDIR /app/frontend
RUN npm run test

# Stage 4: production
FROM nginx:alpine AS production
COPY --from=build /app/frontend/dist /usr/share/nginx/html
COPY frontend/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=test /app/frontend/package.json /tmp/.tests-passed
EXPOSE 80