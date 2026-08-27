# frontend/

Web app React del progetto, servita in produzione da nginx. Parte di [Habit Tracker](../README.md).

## Italiano

### Descrizione

Interfaccia minimale per creare abitudini, segnarle come completate per il giorno corrente ed eliminarle. Parla col backend tramite path relativi (`/api/...`): in sviluppo locale Vite fa da proxy, in produzione/Docker è nginx a instradare le chiamate verso il servizio `backend`. Mostra un banner di errore visibile in UI in caso di fallimento delle chiamate API.

### Requisiti / versioni

| Componente | Versione |
|---|---|
| Node.js | 20.19 (`node:20.19` negli stage `deps`/`build`/`test`, mai `-alpine`, dettagli sotto) |
| React | 19 |
| Vite | 8 |
| nginx | immagine `nginx:alpine`, stage di produzione |

Librerie principali (`package.json`):
```
react / react-dom          : libreria UI
vite                        : build tool e dev server
@vitejs/plugin-react        : supporto JSX/Fast Refresh in Vite
vitest                      : solo dev, test runner
jsdom                       : solo dev, ambiente DOM simulato per i test
@testing-library/react      : solo dev, rendering/query dei componenti nei test
@testing-library/user-event : solo dev, simulazione interazioni utente
@testing-library/jest-dom   : solo dev, matcher aggiuntivi per le asserzioni
```

### Variabili d'ambiente

Il frontend legge una sola variabile, opzionale:
```dotenv
VITE_API_BASE_URL=   # opzionale, se assente usa '/api' (path relativo)
```
Non serve impostarla per l'esecuzione in Docker: il default `/api` viene risolto correttamente da nginx (dettagli in `nginx.conf` sotto). Va valorizzata solo in casi particolari di sviluppo locale (es. backend su una porta non standard).

Le variabili `VITE_*` vengono sostituite in fase di build (`npm run build`), non lette a runtime nel browser. Il `.env` del frontend è escluso dal `.dockerignore` e non è presente durante `docker build`.

### Come eseguirlo

**Locale, fuori Docker:**
```bash
cd frontend
npm install
npm run dev       # Vite dev server, http://localhost:5173
```
Richiede il backend in esecuzione separatamente (es. `npm run dev` in `backend/`, su `localhost:5000`).

**Docker** (si veda anche il [README principale](../README.md#docker) per l'orchestrazione completa):
```bash
docker compose build frontend
docker compose up -d --build frontend
```
Servito su `http://localhost` (porta 80, mappata da nginx). Il servizio non parte prima che `backend` sia `healthy`.

**Kubernetes**: la stessa immagine gira invariata anche su Kubernetes. L'Ingress instrada tutto il traffico verso questo servizio, e lo split verso `/api/` resta interamente a carico di questo stesso `nginx.conf`, esattamente come in Docker Compose. Dettagli nel [README principale, sezione Kubernetes](../README.md#kubernetes).

**Dockerfile, i quattro stage** (contesto di build: la root del repository, non `frontend/`):
```dockerfile
# Stage 1: deps
FROM node:20.19 AS deps
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
```
Note sui quattro stage:
- `deps`/`build`/`test` usano `node:20.19` senza `-alpine`. Con gli npm workspaces, anche lo stage `deps` del backend installa rolldown (devDependency del frontend nel lockfile condiviso), quindi soffre dello stesso vincolo. Vedi il [README principale](../README.md#note-tecniche).
- `production` resta `nginx:alpine`: questo stage non esegue mai Node, nessun conflitto con rolldown, dimensione finale invariata.
- `test` è referenziato da `production` solo come gate (`COPY --from=test`).
- `.dockerignore` esclude `node_modules/`, `.env`, `dist/` dal contesto di build.

**`nginx.conf`, reverse proxy verso il backend:**
```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri /index.html;
    }

    location /api/ {
        proxy_pass http://backend:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
`proxy_pass` senza path dopo `http://backend:5000` inoltra l'URI originale così com'è (`/api/habits` resta `/api/habits` sul backend). Combacia con le route montate su `/api/habits` lato Express, nessuna riscrittura di path necessaria.

### Struttura interna

```
frontend/
├── package.json
├── vite.config.js          # config Vite + sezione test (Vitest), unico file di config
├── .env                     # override locale opzionale (VITE_API_BASE_URL)
├── .gitignore
├── .oxlintrc.json           # configurazione linter (oxlint)
├── Dockerfile
├── .dockerignore
├── nginx.conf               # reverse proxy, usato solo nello stage production
├── index.html
├── src/
│   ├── main.jsx              # entry point React (creato da Vite)
│   ├── App.jsx                # componente principale: lista, form, gestione errori
│   ├── App.css
│   └── api.js
│       # wrapper fetch verso le route del backend, base URL relativa di default
└── tests/
    ├── setup.js               # import '@testing-library/jest-dom', estende expect
    └── unit/
        └── App.test.jsx
```

### Testing

**Framework:** Vitest, jsdom, React Testing Library, user-event.

**Comandi:**
```bash
npm test           # tutta la suite (vitest run)
```

Le chiamate API (`getHabits`, `createHabit`, `addEntry`, `deleteHabit`) sono mockate con `vi.mock('../../src/api')`: nessuna chiamata di rete reale durante i test, comportamento controllato in ogni test (`mockResolvedValue`/`mockRejectedValue`).

**Risultato attuale:** 5 test, tutti verdi.

| Test | Cosa verifica |
|---|---|
| mostra la lista di abitudini caricate | Rendering della lista dopo il caricamento asincrono iniziale |
| mostra lista vuota quando non ci sono abitudini | Nessun elemento estraneo quando l'API risponde `[]` |
| crea una nuova abitudine quando si compila il form | Submit del form, chiamata a `createHabit` con i parametri corretti |
| elimina un'abitudine quando si clicca sul cestino | Click sul bottone, chiamata a `deleteHabit` con l'id corretto |
| mostra un messaggio di errore se il caricamento fallisce | `getHabits` rifiutata, banner d'errore (`role="alert"`) visibile in UI |

---

## English

### Description

A minimal interface to create habits, mark them done for the current day, and delete them. It talks to the backend via relative paths (`/api/...`): in local development Vite proxies the calls, in production/Docker nginx routes them to the `backend` service. It shows a visible error banner in the UI when API calls fail.

### Requirements / versions

| Component | Version |
|---|---|
| Node.js | 20.19 (`node:20.19` in the `deps`/`build`/`test` stages, never `-alpine`, details below) |
| React | 19 |
| Vite | 8 |
| nginx | `nginx:alpine` image, production stage |

Main libraries (`package.json`):
```
react / react-dom          : UI library
vite                        : build tool and dev server
@vitejs/plugin-react        : JSX/Fast Refresh support in Vite
vitest                      : dev only, test runner
jsdom                       : dev only, simulated DOM environment for tests
@testing-library/react      : dev only, component rendering/querying in tests
@testing-library/user-event : dev only, simulated user interactions
@testing-library/jest-dom   : dev only, extra matchers for assertions
```

### Environment variables

The frontend reads a single, optional variable:
```dotenv
VITE_API_BASE_URL=   # optional, defaults to '/api' (relative path) if absent
```
No need to set it for Docker execution: the `/api` default resolves correctly through nginx (see `nginx.conf` below). It should only be set for specific local dev scenarios (e.g. backend on a non-standard port).

`VITE_*` variables are replaced at build time (`npm run build`), not read in the browser at runtime. The frontend's `.env` is excluded via `.dockerignore` and isn't present during `docker build`.

### How to run it

**Locally, outside Docker:**
```bash
cd frontend
npm install
npm run dev       # Vite dev server, http://localhost:5173
```
Requires the backend running separately (e.g. `npm run dev` in `backend/`, on `localhost:5000`).

**Docker** (see also the [main README](../README.md#docker) for the full orchestration):
```bash
docker compose build frontend
docker compose up -d --build frontend
```
Served at `http://localhost` (port 80, mapped by nginx). The service doesn't start until `backend` is `healthy`.

**Kubernetes**: the same image runs unchanged on Kubernetes too. The Ingress routes all traffic to this service, and the split toward `/api/` stays entirely inside this same `nginx.conf`, exactly as in Docker Compose. Details in the [main README, Kubernetes section](../README.md#kubernetes).

**Dockerfile, the four stages** (build context: the repository root, not `frontend/`):
```dockerfile
# Stage 1: deps
FROM node:20.19 AS deps
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
```
Notes on the four stages:
- `deps`/`build`/`test` use `node:20.19` without `-alpine`. With npm workspaces, the backend's `deps` stage also installs rolldown (the frontend's devDependency, in the shared lockfile), so it's subject to the same constraint. See the [main README](../README.md#technical-notes).
- `production` stays `nginx:alpine`: this stage never runs Node, no conflict with rolldown, final size unaffected.
- `test` is referenced by `production` only as a gate (`COPY --from=test`).
- `.dockerignore` excludes `node_modules/`, `.env`, `dist/` from the build context.

**`nginx.conf`, reverse proxy to the backend:**
```nginx
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files $uri /index.html;
    }

    location /api/ {
        proxy_pass http://backend:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```
`proxy_pass` with no path after `http://backend:5000` forwards the original URI as-is (`/api/habits` stays `/api/habits` on the backend). Matches the routes mounted at `/api/habits` on the Express side, no path rewriting needed.

### Internal structure

```
frontend/
├── package.json
├── vite.config.js          # Vite config + test section (Vitest), single config file
├── .env                     # optional local override (VITE_API_BASE_URL)
├── .gitignore
├── .oxlintrc.json           # linter configuration (oxlint)
├── Dockerfile
├── .dockerignore
├── nginx.conf               # reverse proxy, used only in the production stage
├── index.html
├── src/
│   ├── main.jsx              # React entry point (created by Vite)
│   ├── App.jsx                # main component: list, form, error handling
│   ├── App.css
│   └── api.js
│       # fetch wrapper for the backend routes, relative base URL by default
└── tests/
    ├── setup.js               # import '@testing-library/jest-dom', extends expect
    └── unit/
        └── App.test.jsx
```

### Testing

**Framework:** Vitest, jsdom, React Testing Library, user-event.

**Commands:**
```bash
npm test           # full suite (vitest run)
```

API calls (`getHabits`, `createHabit`, `addEntry`, `deleteHabit`) are mocked with `vi.mock('../../src/api')`: no real network calls during tests, behavior controlled per test (`mockResolvedValue`/`mockRejectedValue`).

**Current result:** 5 tests, all passing.

| Test | What it checks |
|---|---|
| shows the loaded list of habits | List renders after the initial async load |
| shows an empty list when there are no habits | No stray elements when the API returns `[]` |
| creates a new habit when the form is filled | Form submit, `createHabit` called with the right parameters |
| deletes a habit when the trash icon is clicked | Click on the button, `deleteHabit` called with the correct id |
| shows an error message if loading fails | `getHabits` rejected, error banner (`role="alert"`) visible in the UI |