# Habit Tracker

Applicazione a 3 livelli (React + Node/Express + MongoDB) per il tracciamento di abitudini quotidiane.

*Progetto didattico, pensato per essere esteso nel tempo con nuove tecnologie (orchestrazione, CI/CD, infrastruttura cloud, monitoring).*

## Italiano

### Descrizione

Un'app minimale per registrare abitudini giornaliere (es. "Bere 2L d'acqua") e segnarle come completate giorno per giorno. Il frontend React comunica con un backend REST Node/Express, che persiste i dati su MongoDB.

Il focus del progetto è la containerizzazione: Dockerfile multi-stage, orchestrazione con Docker Compose, gestione di rete, segreti e persistenza tra i tre servizi.

### Stack tecnologico

- **Frontend**: React 19, Vite, servito in produzione da nginx
- **Backend**: Node.js 20, Express, Mongoose
- **Database**: MongoDB 7
- **Test**: Vitest (frontend e backend), Supertest, mongodb-memory-server, React Testing Library
- **Containerizzazione**: Docker, Docker Compose

### Architettura

```
Browser
   │  HTTP :80
   ▼
frontend (nginx)
   │  proxy /api/ → backend:5000
   ▼
backend (Express)
   │  :27017
   ▼
mongodb
```

Il browser comunica solo con nginx. Le chiamate a `/api/...` vengono inoltrate al servizio `backend` sulla rete interna di Compose.

### Struttura del repository

```
habit-tracker/
├── README.md                    # questo file
├── docker-compose.yml           # orchestrazione dei 3 servizi
├── .env.example                 # template variabili lette da Compose (credenziali Mongo)
├── .gitignore
├── package.json                 # script aggregatore: lancia i test di backend + frontend
│
├── backend/                     # dettagli in backend/README.md
│   ├── Dockerfile                # multi-stage: build → test → production
│   ├── .dockerignore
│   ├── .env                      # solo per esecuzione locale fuori Docker
│   ├── src/
│   │   ├── app.js                # app Express (senza side-effect, importabile nei test)
│   │   ├── server.js             # entry point reale: connectDB() + app.listen()
│   │   ├── db.js                 # connessione MongoDB
│   │   ├── models/
│   │   │   ├── Habit.js
│   │   │   └── Entry.js
│   │   └── routes/
│   │       └── habitsRoute.js
│   └── tests/
│       ├── setup.js              # MongoDB in-memory condiviso tra i test
│       ├── unit/                 # test sui modelli, isolati
│       └── integration/          # test sulle route HTTP (Supertest)
│
└── frontend/                    # dettagli in frontend/README.md
    ├── Dockerfile                 # multi-stage: build (Node) → test → production (nginx)
    ├── .dockerignore
    ├── .env                       # override locale opzionale (VITE_API_BASE_URL)
    ├── .gitignore
    ├── .oxlintrc.json              # configurazione linter (oxlint)
    ├── nginx.conf                  # reverse proxy /api/ → backend:5000
    ├── src/
    │   ├── App.jsx
    │   ├── App.css
    │   └── api.js                  # wrapper fetch, base URL relativa di default
    └── tests/
        ├── setup.js                # import '@testing-library/jest-dom'
        └── unit/
            └── App.test.jsx
```

### Docker

I dettagli implementativi specifici di ciascun servizio sono nei rispettivi README, qui c'è la visione d'insieme dell'orchestrazione.

#### Servizi

| Servizio | container_name | Reti | Porta pubblicata |
|---|---|---|---|
| `mongodb` | `mongodb` | `backend-net` | nessuna |
| `backend` | `backend` | `backend-net`, `frontend-net` | nessuna |
| `frontend` | `frontend` | `frontend-net` | `80:80` |

Tutti i servizi hanno `restart: unless-stopped`.

#### Immagini e multi-stage build

Sia `backend/Dockerfile` che `frontend/Dockerfile` sono strutturati in **tre stage**:

| Stage | Scopo | Finisce nell'immagine finale? |
|---|---|---|
| `build` | Installa tutte le dipendenze (incluse quelle di sviluppo) e prepara il codice | No |
| `test` | Eredita da `build`, esegue la suite di test (`npm run test`) | No |
| `production` | Immagine finale, solo quanto necessario per l'esecuzione | Sì |

Lo stage `test` non è mai referenziato da `COPY --from=test` né da `--target test` in una build normale. Docker lo ignora in `docker compose build`. Va invocato esplicitamente quando serve:
```bash
docker build --target test -t habit-tracker-backend-test ./backend
```

**Backend** (`node:20.18-alpine` in tutti gli stage): lo stage `production` reinstalla le dipendenze da zero con `npm ci --omit=dev` invece di copiare i `node_modules` dello stage `build`. L'immagine finale non contiene `devDependencies`.

**Frontend**: lo stage `build` usa `node:20` (non `-alpine`). Lo stage `production` è `nginx:alpine`: l'immagine finale non contiene Node né `node_modules`, solo i file statici compilati (`dist/`).

In entrambi i Dockerfile, `package*.json` viene copiato e installato prima del resto del codice sorgente: il layer delle dipendenze resta in cache quando cambia solo il codice applicativo.

#### Rete

Due reti Compose separate:
```yaml
networks:
  frontend-net:   # frontend ↔ backend
  backend-net:    # backend ↔ mongodb
```
Il servizio `backend` è l'unico presente su entrambe le reti. `frontend` e `mongodb` non hanno visibilità diretta l'uno sull'altro.

#### Persistenza

```yaml
volumes:
  mongo-data:
```
Named volume montato su `/data/db` dentro il container `mongodb`. `docker compose down` preserva i dati; solo `docker compose down -v` li cancella.

#### Variabili d'ambiente e segreti

MongoDB gira con autenticazione attiva, valorizzata da un `.env` alla radice del progetto (mai committato):
```dotenv
MONGO_ROOT_USER=admin
MONGO_ROOT_PASSWORD=CHANGE_ME
MONGO_DB_NAME=habittracker
```
Compose interpola queste variabili nel servizio `mongodb` e nella `MONGO_URI` passata al `backend`:
```
mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@mongodb:27017/${MONGO_DB_NAME}?authSource=admin
```
Nessuna credenziale è hardcoded nei Dockerfile o nel `docker-compose.yml`.

Le credenziali di root vengono applicate solo alla prima inizializzazione di un volume vuoto. Un cambio di password successivo richiede `docker compose down -v`.

#### Healthcheck e ordine di avvio

`depends_on` con `condition: service_healthy` garantisce l'ordine:
```
mongodb (healthy) → backend (healthy) → frontend
```

| Servizio | Healthcheck |
|---|---|
| `mongodb` | `mongosh -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval "db.adminCommand('ping')"` |
| `backend` | `wget -qO- http://localhost:5000/api/health` |
| `frontend` | `wget -qO- http://localhost:80` |

#### Limiti di risorse

| Servizio | mem_limit | cpus |
|---|---|---|
| `mongodb` | 512m | 1.0 |
| `backend` | 256m | 0.5 |
| `frontend` | 128m | 0.3 |

Verifica con `docker stats`.

#### Comandi utili

```bash
docker compose up --build              # build + avvio di tutti i servizi
docker compose up --build -d           # come sopra, in background
docker compose logs -f backend         # segui i log di un servizio specifico
docker compose ps                      # stato/healthiness dei servizi
docker compose down                    # ferma tutto, preserva i dati
docker compose down -v                 # ferma tutto, cancella anche il volume Mongo
docker images | grep habit-tracker     # dimensioni delle immagini costruite
```

#### Note tecniche

**Vite/rolldown e Alpine**: la build del frontend fallisce su `node:20-alpine` con un errore relativo a `@rolldown/binding-linux-x64-musl` (binario nativo compilato per glibc, incompatibile con `musl`). Lo stage `build` del frontend usa `node:20`; lo stage `production` resta `nginx:alpine`, la dimensione dell'immagine finale non cambia.

**Variabili `VITE_*`**: vengono sostituite in fase di build (`npm run build`), non lette a runtime nel browser. Il `.env` del frontend è escluso dal `.dockerignore` e non è presente durante la build in Docker. `api.js` usa `/api` come valore di default (`import.meta.env.VITE_API_BASE_URL || '/api'`).

### Setup e avvio rapido

```bash
git clone <url-repo>
cd habit-tracker
cp .env.example .env   # e compilare MONGO_ROOT_PASSWORD

docker compose up --build
docker compose ps      # verificare che tutti i servizi siano "healthy"
```

App disponibile su `http://localhost`.

### Testing

Suite di test automatizzata su backend e frontend, lanciabile in un unico comando dalla root:
```bash
npm test
```
(equivalente a `npm run test:backend && npm run test:frontend`, si ferma al primo fallimento). Dettagli su framework, strategia di mock e copertura nei README di [`backend/`](backend/README.md#testing) e [`frontend/`](frontend/README.md#testing).

---

## English

### Description

A minimal app for logging daily habits (e.g. "Drink 2L of water") and marking them done day by day. The React frontend talks to a Node/Express REST backend, which persists data to MongoDB.

The focus of this project is containerization: multi-stage Dockerfiles, Docker Compose orchestration, network/secrets/persistence management across the three services.

### Tech stack

- **Frontend**: React 19, Vite, served in production by nginx
- **Backend**: Node.js 20, Express, Mongoose
- **Database**: MongoDB 7
- **Testing**: Vitest (frontend and backend), Supertest, mongodb-memory-server, React Testing Library
- **Containerization**: Docker, Docker Compose

### Architecture

```
Browser
   │  HTTP :80
   ▼
frontend (nginx)
   │  proxy /api/ → backend:5000
   ▼
backend (Express)
   │  :27017
   ▼
mongodb
```

The browser only talks to nginx. Calls to `/api/...` are forwarded to the `backend` service on the internal Compose network.

### Repository structure

```
habit-tracker/
├── README.md                    # this file
├── docker-compose.yml           # orchestration of the 3 services
├── .env.example                 # template for variables read by Compose (Mongo credentials)
├── .gitignore
├── package.json                 # aggregator script: runs backend + frontend tests
│
├── backend/                     # details in backend/README.md
│   ├── Dockerfile                # multi-stage: build → test → production
│   ├── .dockerignore
│   ├── .env                      # only for local execution outside Docker
│   ├── src/
│   │   ├── app.js                # Express app (no side effects, importable in tests)
│   │   ├── server.js             # real entry point: connectDB() + app.listen()
│   │   ├── db.js                 # MongoDB connection
│   │   ├── models/
│   │   │   ├── Habit.js
│   │   │   └── Entry.js
│   │   └── routes/
│   │       └── habitsRoute.js
│   └── tests/
│       ├── setup.js              # in-memory MongoDB shared across tests
│       ├── unit/                 # isolated model tests
│       └── integration/          # HTTP route tests (Supertest)
│
└── frontend/                    # details in frontend/README.md
    ├── Dockerfile                 # multi-stage: build (Node) → test → production (nginx)
    ├── .dockerignore
    ├── .env                       # optional local override (VITE_API_BASE_URL)
    ├── .gitignore
    ├── .oxlintrc.json              # linter configuration (oxlint)
    ├── nginx.conf                  # reverse proxy /api/ → backend:5000
    ├── src/
    │   ├── App.jsx
    │   ├── App.css
    │   └── api.js                  # fetch wrapper, relative base URL by default
    └── tests/
        ├── setup.js                # import '@testing-library/jest-dom'
        └── unit/
            └── App.test.jsx
```

### Docker

Implementation details specific to each service live in the respective READMEs, this is the orchestration overview.

#### Services

| Service | container_name | Networks | Published port |
|---|---|---|---|
| `mongodb` | `mongodb` | `backend-net` | none |
| `backend` | `backend` | `backend-net`, `frontend-net` | none |
| `frontend` | `frontend` | `frontend-net` | `80:80` |

All services have `restart: unless-stopped`.

#### Images and multi-stage builds

Both `backend/Dockerfile` and `frontend/Dockerfile` follow a **three-stage** structure:

| Stage | Purpose | Ends up in the final image? |
|---|---|---|
| `build` | Installs all dependencies (including dev ones) and prepares the code | No |
| `test` | Inherits from `build`, runs the test suite (`npm run test`) | No |
| `production` | Final image, only what's needed at runtime | Yes |

The `test` stage is never referenced by `COPY --from=test` nor `--target test` in a normal build. Docker skips it in `docker compose build`. It's invoked explicitly when needed:
```bash
docker build --target test -t habit-tracker-backend-test ./backend
```

**Backend** (`node:20.18-alpine` in every stage): the `production` stage reinstalls dependencies from scratch with `npm ci --omit=dev` instead of copying `node_modules` from the `build` stage. The final image contains no `devDependencies`.

**Frontend**: the `build` stage uses `node:20` (not `-alpine`). The `production` stage is `nginx:alpine`: the final image contains no Node or `node_modules`, only the compiled static files (`dist/`).

In both Dockerfiles, `package*.json` is copied and installed before the rest of the source code: the dependency layer stays cached when only application code changes.

#### Networking

Two separate Compose networks:
```yaml
networks:
  frontend-net:   # frontend ↔ backend
  backend-net:    # backend ↔ mongodb
```
The `backend` service is the only one present on both networks. `frontend` and `mongodb` have no direct visibility of each other.

#### Persistence

```yaml
volumes:
  mongo-data:
```
A named volume mounted at `/data/db` inside the `mongodb` container. `docker compose down` preserves data; only `docker compose down -v` deletes it.

#### Environment variables and secrets

MongoDB runs with authentication enabled, set via a root-level `.env` file (never committed):
```dotenv
MONGO_ROOT_USER=admin
MONGO_ROOT_PASSWORD=CHANGE_ME
MONGO_DB_NAME=habittracker
```
Compose interpolates these into the `mongodb` service and into the `MONGO_URI` passed to `backend`:
```
mongodb://${MONGO_ROOT_USER}:${MONGO_ROOT_PASSWORD}@mongodb:27017/${MONGO_DB_NAME}?authSource=admin
```
No credentials are hardcoded in the Dockerfiles or `docker-compose.yml`.

Root credentials are applied only on the first initialization of an empty volume. Changing the password afterwards requires `docker compose down -v`.

#### Healthchecks and startup order

`depends_on` with `condition: service_healthy` guarantees the order:
```
mongodb (healthy) → backend (healthy) → frontend
```

| Service | Healthcheck |
|---|---|
| `mongodb` | `mongosh -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval "db.adminCommand('ping')"` |
| `backend` | `wget -qO- http://localhost:5000/api/health` |
| `frontend` | `wget -qO- http://localhost:80` |

#### Resource limits

| Service | mem_limit | cpus |
|---|---|---|
| `mongodb` | 512m | 1.0 |
| `backend` | 256m | 0.5 |
| `frontend` | 128m | 0.3 |

Verify with `docker stats`.

#### Useful commands

```bash
docker compose up --build              # build + start all services
docker compose up --build -d           # same, detached
docker compose logs -f backend         # follow a specific service's logs
docker compose ps                      # status/healthiness of services
docker compose down                    # stop everything, keep data
docker compose down -v                 # stop everything, also delete the Mongo volume
docker images | grep habit-tracker     # size of built images
```

#### Technical notes

**Vite/rolldown and Alpine**: the frontend build fails on `node:20-alpine` with an error about `@rolldown/binding-linux-x64-musl` (a native binary compiled for glibc, incompatible with `musl`). The frontend's `build` stage uses `node:20`; the `production` stage stays `nginx:alpine`, so the final image size is unaffected.

**`VITE_*` variables**: replaced at build time (`npm run build`), not read in the browser at runtime. The frontend's `.env` is excluded via `.dockerignore` and isn't present during the Docker build. `api.js` uses `/api` as the default value (`import.meta.env.VITE_API_BASE_URL || '/api'`).

### Quick setup

```bash
git clone <repo-url>
cd habit-tracker
cp .env.example .env   # and fill in MONGO_ROOT_PASSWORD

docker compose up --build
docker compose ps      # verify all services report "healthy"
```

App available at `http://localhost`.

### Testing

Automated test suite for both backend and frontend, runnable with a single command from the root:
```bash
npm test
```
(equivalent to `npm run test:backend && npm run test:frontend`, stops at the first failure). Details on framework, mocking strategy and coverage in the [`backend/`](backend/README.md#testing) and [`frontend/`](frontend/README.md#testing) READMEs.