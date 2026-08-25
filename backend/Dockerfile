# Stage 1: deps
# npm ci con i workspaces ha bisogno di vedere TUTTI i package.json elencati nel lockfile (backend + frontend),
# anche se questa immagine conterrà solo il backend.
FROM node:20.19-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
RUN npm ci

# Stage 2: build
FROM deps AS build
COPY backend ./backend

# Stage 3: test
FROM build AS test
WORKDIR /app/backend
RUN npm run test

# Stage 4: production
FROM node:20.19-alpine AS production
WORKDIR /app
COPY package.json package-lock.json ./
COPY backend/package.json ./backend/
COPY frontend/package.json ./frontend/
RUN npm ci --omit=dev \
    && apk update && apk upgrade --no-cache \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx
COPY backend ./backend
COPY --from=test /app/backend/package.json /tmp/.tests-passed
WORKDIR /app/backend
EXPOSE 5000
USER node
CMD ["node", "src/server.js"]