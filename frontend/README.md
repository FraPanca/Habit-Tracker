# frontend/

Web app React del progetto, servita in produzione da nginx. Parte di [Habit Tracker](../README.md).

## Italiano

### Descrizione

Interfaccia minimale per creare abitudini, segnarle come completate per il giorno corrente ed eliminarle. Parla col backend tramite path relativi (`/api/...`): in sviluppo locale Vite fa da proxy, in produzione/Docker è nginx a instradare le chiamate verso il servizio `backend`. Mostra un banner di errore visibile in UI in caso di fallimento delle chiamate API.

### Requisiti / versioni

| Componente | Versione |
|---|---|
| Node.js | 20 (immagine Docker `node:20` nello stage di build, non `-alpine`, vedi sotto) |
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
Non serve impostarla per l'esecuzione in Docker: il default `/api` viene risolto correttamente da nginx (vedi `nginx.conf` sotto). Va valorizzata solo in casi particolari di sviluppo locale (es. backend su una porta non standard).

Le variabili `VITE_*` vengono sostituite in fase di build (`npm run build`), non lette a runtime nel browser. Il `.env` del frontend è escluso dal `.dockerignore` e non è presente durante `docker build`.

### Come eseguirlo

**Locale, fuori Docker:**
```bash
cd frontend
npm install
npm run dev       # Vite dev server, http://localhost:5173
```
Richiede il backend in esecuzione separatamente (es. `npm run dev` in `backend/`, su `localhost:5000`).

**Docker** (vedi anche il [README principale](../README.md#docker) per l'orchestrazione completa):
```bash
docker compose build frontend
docker compose up -d --build frontend
```
Servito su `http://localhost` (porta 80, mappata da nginx). Il servizio non parte prima che `backend` sia `healthy`.

**Dockerfile, i tre stage:**
```dockerfile
# Stage 1: build
FROM node:20 AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: test
FROM build AS test
RUN npm run test

# Stage 3: production
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```
Note sui tre stage:
- Lo stage `build` usa `node:20`, non `node:20-alpine` (unica eccezione rispetto al backend). Il bundler interno di Vite (rolldown) richiede un binario nativo compilato per glibc, non disponibile in un ambiente musl come Alpine. Dettaglio dell'errore nel README principale, sezione "Note tecniche".
- La dimensione dell'immagine finale non è impattata: lo stage `build` viene scartato interamente dal multi-stage, l'immagine consegnata (`nginx:alpine`, stage `production`) non contiene mai Node.
- `COPY nginx.conf /etc/nginx/conf.d/default.conf` copia direttamente dal contesto host, non da uno stage precedente.
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
├── package-lock.json
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
| Node.js | 20 (Docker image `node:20` in the build stage, not `-alpine`, see below) |
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

**Dockerfile, the three stages:**
```dockerfile
# Stage 1: build
FROM node:20 AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: test
FROM build AS test
RUN npm run test

# Stage 3: production
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
```
Notes on the three stages:
- The `build` stage uses `node:20`, not `node:20-alpine` (the one exception compared to the backend). Vite's internal bundler (rolldown) requires a native binary compiled for glibc, unavailable in a musl environment like Alpine. Error detail in the main README, "Technical notes" section.
- Final image size is unaffected: the `build` stage is entirely discarded by the multi-stage build, the shipped image (`nginx:alpine`, `production` stage) never contains Node.
- `COPY nginx.conf /etc/nginx/conf.d/default.conf` copies directly from the host context, not from a previous stage.
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
├── package-lock.json
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