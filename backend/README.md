# backend/

API REST del progetto, in Node.js/Express + MongoDB (Mongoose). Parte di [Habit Tracker](../README.md).

## Italiano

### Descrizione

Espone le operazioni CRUD su due risorse: `Habit` (definizione di un'abitudine da monitorare) ed `Entry` (registrazione giornaliera del valore di un'abitudine), persistite su MongoDB. `app.js` (definizione Express, senza side-effect) è separato da `server.js` (entry point reale, connessione DB e avvio del listener): l'app è importabile nei test di integrazione senza aprire connessioni reali.

### Requisiti / versioni

| Componente | Versione |
|---|---|
| Node.js | 20.18 (immagine Docker `node:20.18-alpine`) |
| MongoDB | 7 |

Librerie principali (`package.json`):
```
express    : server HTTP
mongoose   : ODM MongoDB
cors       : abilitazione CORS (sviluppo locale, frontend/backend su porte diverse)
dotenv     : caricamento .env locale
nodemon    : solo dev, riavvio automatico
vitest     : solo dev, test runner
supertest  : solo dev, test di integrazione HTTP
mongodb-memory-server : solo dev, MongoDB effimero in RAM per i test
```

### Variabili d'ambiente

**In esecuzione Docker**: nessun `.env` nel container. `PORT` e `MONGO_URI` sono passate da `docker-compose.yml` tramite `environment:`, con `MONGO_URI` che punta al servizio `mongodb` (non `localhost`) e include le credenziali interpolate dal `.env` alla radice del repository. Dettagli completi nel [README principale](../README.md#variabili-dambiente-e-segreti).

**Solo per esecuzione locale fuori Docker** (`backend/.env`, mai letto dal container):
```dotenv
PORT=5000
MONGO_URI=mongodb://localhost:27017/habittracker
```

### Come eseguirlo

**Locale, fuori Docker** (richiede un'istanza MongoDB raggiungibile, anche non autenticata):
```bash
cd backend
# creare .env con PORT e MONGO_URI (vedi sezione "Variabili d'ambiente")
npm install
npm run dev             # nodemon, riavvio automatico
# oppure: npm start      (nessun riavvio automatico)
```

**Docker** (vedi anche il [README principale](../README.md#docker) per l'orchestrazione completa):
```bash
docker compose build backend
docker compose up -d --build backend
docker compose logs -f backend
```
Log atteso all'avvio: `MongoDB connesso` → `Server avviato sulla porta 5000`. Il servizio non parte prima che `mongodb` sia `healthy`.

**Dockerfile, i tre stage** (`node:20.18-alpine` in tutti):
```dockerfile
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
```
Note sui tre stage:
- `COPY package*.json ./` seguito da `RUN npm ci` avviene prima di `COPY . .`. Il layer delle dipendenze resta in cache quando cambia solo il codice sorgente.
- Lo stage `production` non copia `node_modules` dallo stage `build`: reinstalla da zero con `--omit=dev`. L'immagine finale non contiene dipendenze di sviluppo (test runner incluso).
- `USER node`: il processo gira con l'utente non privilegiato predefinito nell'immagine `node:alpine`.
- `.dockerignore` esclude `node_modules/` e `.env` dal contesto di build.

### Struttura interna

```
backend/
├── package.json
├── package-lock.json
├── vitest.config.js
├── .env
├── Dockerfile
├── .dockerignore
├── src/
│   ├── app.js
│   │   # app Express pura: middleware, mount delle routes. Nessuna connessione DB,
│   │   # nessun app.listen() : importabile nei test senza side-effect
│   ├── server.js
│   │   # entry point reale: connectDB() + app.listen(), usato solo in esecuzione
│   ├── db.js
│   │   # connessione MongoDB (Mongoose)
│   ├── models/
│   │   ├── Habit.js
│   │   │   # { name, type: "boolean"|"numeric", targetValue?, createdAt }
│   │   └── Entry.js
│   │       # { habitId (ref Habit), date: "YYYY-MM-DD", value, notedAt }
│   │       # indice unique composito {habitId, date}: una sola entry per habit/giorno
│   │       # validator custom su value: accetta solo boolean o number
│   └── routes/
│       └── habitsRoute.js
│           # tutte le route sotto /api/habits, vedi tabella API sotto
└── tests/
    ├── setup.js
    │   # MongoDB in-memory (mongodb-memory-server) condiviso da tutti i test,
    │   # pulizia delle collection dopo ogni test (afterEach) per isolamento
    ├── unit/
    │   ├── habit.model.test.js
    │   └── entry.model.test.js
    └── integration/
        └── habits.routes.test.js
```

### API

Base path: `/api/habits`

| Metodo | Path | Descrizione | Status atteso |
|---|---|---|---|
| `GET` | `/api/health` | Healthcheck applicativo | `200` |
| `POST` | `/api/habits` | Crea una nuova abitudine | `201` |
| `GET` | `/api/habits` | Lista tutte le abitudini | `200` |
| `DELETE` | `/api/habits/:id` | Elimina un'abitudine e le sue entry | `204` |
| `POST` | `/api/habits/:id/entries` | Registra/aggiorna (upsert) il valore di un giorno | `201` |
| `GET` | `/api/habits/:id/entries` | Storico entry di un'abitudine, filtro opzionale `?from=&to=` | `200` |

`POST /:id/entries` usa `findOneAndUpdate` con `upsert: true` sulla coppia `{habitId, date}`: chiamare due volte lo stesso giorno aggiorna l'entry esistente, non ne crea una seconda. Il vincolo è garantito anche a livello di indice DB.

### Testing

**Framework:** Vitest, Supertest per i test di integrazione HTTP, `mongodb-memory-server` per un MongoDB reale ma effimero.

**Comandi:**
```bash
npm test          # tutta la suite (vitest run)
npm run test:watch # riesecuzione automatica sui file modificati
```

Nessun `.env` reale necessario. `mongodb-memory-server` avvia un'istanza MongoDB locale in RAM ad ogni run; al primo avvio scarica il binario. `hookTimeout` è impostato a 60s in `vitest.config.js`. Ogni test parte con collection pulite (`afterEach` in `tests/setup.js`).

**Risultato attuale:** 22 test, tutti verdi.

| File | N. test | Cosa verifica |
|---|---|---|
| `unit/habit.model.test.js` | 6 | Validazioni schema `Habit` (`name`/`type` richiesti, `enum` su `type`, `trim`, `targetValue`) |
| `unit/entry.model.test.js` | 8 | Validazioni schema `Entry`, validator custom su `value`, vincolo di unicità `{habitId, date}` |
| `integration/habits.routes.test.js` | 8 | CRUD completo via HTTP reale (Supertest): creazione, lista, upsert delle entry, storico, eliminazione |

---

## English

### Description

Exposes CRUD operations on two resources: `Habit` (the definition of a habit to track) and `Entry` (a daily record of a habit's value), persisted in MongoDB. `app.js` (Express setup, no side effects) is kept separate from `server.js` (real entry point, DB connection and listener startup): the app is importable in integration tests without opening real connections.

### Requirements / versions

| Component | Version |
|---|---|
| Node.js | 20.18 (Docker image `node:20.18-alpine`) |
| MongoDB | 7 |

Main libraries (`package.json`):
```
express    : HTTP server
mongoose   : MongoDB ODM
cors       : CORS support (local dev, frontend/backend on different ports)
dotenv     : local .env loading
nodemon    : dev only, automatic restart
vitest     : dev only, test runner
supertest  : dev only, HTTP integration tests
mongodb-memory-server : dev only, in-RAM ephemeral MongoDB for tests
```

### Environment variables

**In Docker**: no `.env` inside the container. `PORT` and `MONGO_URI` are passed by `docker-compose.yml` via `environment:`, with `MONGO_URI` pointing at the `mongodb` service (not `localhost`) and including credentials interpolated from the repository's root `.env`. Full details in the [main README](../README.md#environment-variables-and-secrets).

**Only for local execution outside Docker** (`backend/.env`, never read by the container):
```dotenv
PORT=5000
MONGO_URI=mongodb://localhost:27017/habittracker
```

### How to run it

**Locally, outside Docker** (requires a reachable MongoDB instance, unauthenticated is fine):
```bash
cd backend
# create .env with PORT and MONGO_URI (see "Environment variables" section)
npm install
npm run dev             # nodemon, automatic restart
# or: npm start          (no automatic restart)
```

**Docker** (see also the [main README](../README.md#docker) for the full orchestration):
```bash
docker compose build backend
docker compose up -d --build backend
docker compose logs -f backend
```
Expected startup log: `MongoDB connesso` → `Server avviato sulla porta 5000`. The service doesn't start until `mongodb` is `healthy`.

**Dockerfile, the three stages** (`node:20.18-alpine` throughout):
```dockerfile
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
```
Notes on the three stages:
- `COPY package*.json ./` followed by `RUN npm ci` happens before `COPY . .`. The dependency layer stays cached when only source code changes.
- The `production` stage does not copy `node_modules` from the `build` stage: it reinstalls from scratch with `--omit=dev`. The final image contains no dev dependencies (including the test runner).
- `USER node`: the process runs as the unprivileged user predefined in the `node:alpine` image.
- `.dockerignore` excludes `node_modules/` and `.env` from the build context.

### Internal structure

```
backend/
├── package.json
├── package-lock.json
├── vitest.config.js
├── .env
├── Dockerfile
├── .dockerignore
├── src/
│   ├── app.js
│   │   # pure Express app: middleware, route mounting. No DB connection,
│   │   # no app.listen() : importable in tests without side effects
│   ├── server.js
│   │   # real entry point: connectDB() + app.listen(), used only at runtime
│   ├── db.js
│   │   # MongoDB connection (Mongoose)
│   ├── models/
│   │   ├── Habit.js
│   │   │   # { name, type: "boolean"|"numeric", targetValue?, createdAt }
│   │   └── Entry.js
│   │       # { habitId (ref Habit), date: "YYYY-MM-DD", value, notedAt }
│   │       # unique composite index {habitId, date}: one entry per habit/day
│   │       # custom validator on value: accepts only boolean or number
│   └── routes/
│       └── habitsRoute.js
│           # all routes under /api/habits, see API table below
└── tests/
    ├── setup.js
    │   # in-memory MongoDB (mongodb-memory-server) shared across all tests,
    │   # collections cleared after every test (afterEach) for isolation
    ├── unit/
    │   ├── habit.model.test.js
    │   └── entry.model.test.js
    └── integration/
        └── habits.routes.test.js
```

### API

Base path: `/api/habits`

| Method | Path | Description | Expected status |
|---|---|---|---|
| `GET` | `/api/health` | Application healthcheck | `200` |
| `POST` | `/api/habits` | Create a new habit | `201` |
| `GET` | `/api/habits` | List all habits | `200` |
| `DELETE` | `/api/habits/:id` | Delete a habit and its entries | `204` |
| `POST` | `/api/habits/:id/entries` | Record/update (upsert) a day's value | `201` |
| `GET` | `/api/habits/:id/entries` | A habit's entry history, optional `?from=&to=` filter | `200` |

`POST /:id/entries` uses `findOneAndUpdate` with `upsert: true` on the `{habitId, date}` pair: calling it twice for the same day updates the existing entry instead of creating a second one. The constraint is enforced at the DB index level too.

### Testing

**Framework:** Vitest, Supertest for HTTP integration tests, `mongodb-memory-server` for a real but ephemeral MongoDB.

**Commands:**
```bash
npm test           # full suite (vitest run)
npm run test:watch # re-run automatically on file changes
```

No real `.env` needed. `mongodb-memory-server` spins up a local in-RAM MongoDB instance on every run; it downloads the binary on first use. `hookTimeout` is set to 60s in `vitest.config.js`. Every test starts with clean collections (`afterEach` in `tests/setup.js`).

**Current result:** 22 tests, all passing.

| File | # tests | What it checks |
|---|---|---|
| `unit/habit.model.test.js` | 6 | `Habit` schema validation (`name`/`type` required, `type` enum, `trim`, `targetValue`) |
| `unit/entry.model.test.js` | 8 | `Entry` schema validation, custom validator on `value`, `{habitId, date}` uniqueness constraint |
| `integration/habits.routes.test.js` | 8 | Full CRUD over real HTTP (Supertest): creation, listing, entry upsert, history, deletion |