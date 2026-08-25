# Habit Tracker

Applicazione a 3 livelli (React + Node/Express + MongoDB) per il tracciamento di abitudini quotidiane.

*Progetto didattico, pensato per essere esteso nel tempo con nuove tecnologie (CI/CD, infrastruttura cloud, monitoring).*

## Italiano

### Descrizione

Un'app minimale per registrare abitudini giornaliere (es. "Bere 2L d'acqua") e segnarle come completate giorno per giorno. Il frontend React comunica con un backend REST Node/Express, che persiste i dati su MongoDB.

Il focus del progetto è la containerizzazione e l'orchestrazione: Dockerfile multi-stage, gestione di rete, segreti e persistenza tra i tre servizi, orchestrati con Docker Compose e, in alternativa, con Kubernetes e con un chart Helm che ne parametrizza il deploy e aggiunge l'autoscaling.

### Stack tecnologico

- **Frontend**: React 19, Vite, servito in produzione da nginx
- **Backend**: Node.js 20, Express, Mongoose
- **Database**: MongoDB 7
- **Test**: Vitest (frontend e backend), Supertest, mongodb-memory-server, React Testing Library
- **Containerizzazione**: Docker, Docker Compose
- **Orchestrazione**: Kubernetes (manifest raw in `k8s/`) e Helm (chart in `charts/habit-tracker/`), entrambi validati su un cluster locale minikube

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
├── frontend/                    # dettagli in frontend/README.md
│   ├── Dockerfile                 # multi-stage: build (Node) → test → production (nginx)
│   ├── .dockerignore
│   ├── .env                       # override locale opzionale (VITE_API_BASE_URL)
│   ├── .gitignore
│   ├── .oxlintrc.json              # configurazione linter (oxlint)
│   ├── nginx.conf                  # reverse proxy /api/ → backend:5000
│   ├── src/
│   │   ├── App.jsx
│   │   ├── App.css
│   │   └── api.js                  # wrapper fetch, base URL relativa di default
│   └── tests/
│       ├── setup.js                # import '@testing-library/jest-dom'
│       └── unit/
│           └── App.test.jsx
│
├── k8s/                         # manifest Kubernetes raw, tenuti come riferimento (vedi charts/ per il deploy con Helm)
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml         # NODE_ENV, PORT, MONGO_DB_NAME (dato non sensibile)
│   ├── 02-secret.yaml            # credenziali MongoDB (dato sensibile)
│   ├── 03-mongodb.yaml           # PVC + Deployment (1 replica) + Service
│   ├── 04-backend.yaml           # Deployment (2 repliche) + Service
│   ├── 05-frontend.yaml          # Deployment + Service
│   ├── 06-ingress.yaml           # instrada tutto verso frontend
│   └── 07-networkpolicy.yaml     # isola il traffico tra i tre livelli
│
└── charts/habit-tracker/        # deploy con Helm, dettagli nella sezione "Helm" sotto
    ├── Chart.yaml
    ├── values.yaml                    # valori di default
    ├── values-dev.yaml                # override per test locale (minikube/kind)
    ├── values-secret.yaml.example     # template credenziali Mongo, NON committare la copia compilata
    └── templates/
        ├── _helpers.tpl               # label comuni + risoluzione nomi (secret, service mongo)
        ├── namespace.yaml             # opzionale, disabilitato di default
        ├── configmap.yaml
        ├── secret.yaml                # generato solo se non usi un Secret esterno esistente
        ├── mongodb-pvc.yaml
        ├── mongodb-deployment.yaml
        ├── mongodb-service.yaml
        ├── backend-deployment.yaml
        ├── backend-service.yaml
        ├── backend-hpa.yaml           # Horizontal Pod Autoscaler
        ├── frontend-deployment.yaml
        ├── frontend-service.yaml
        ├── frontend-hpa.yaml          # disabilitato di default
        ├── ingress.yaml
        ├── networkpolicy.yaml
        └── NOTES.txt                  # istruzioni post-install/upgrade
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

Verificabile con `docker stats`.

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

#### Registry

Le immagini di `backend` e `frontend` sono pubblicate su GitHub Container Registry, referenziate nel `docker-compose.yml` accanto a `build:`:

```yaml
backend:
  build: ./backend
  image: ghcr.io/frapanca/habit-tracker-backend:latest

frontend:
  build: ./frontend
  image: ghcr.io/frapanca/habit-tracker-frontend:latest
```

`mongodb` resta escluso: usa l'immagine ufficiale `mongo:7`, non va pushata.

Build e push sono due comandi separati:
```bash
docker compose build backend frontend
docker compose push backend frontend
```

Richiede un login preventivo:
```bash
docker login ghcr.io -u <username>
```
(con un Personal Access Token con permesso `write:packages`, mai una password in chiaro)

Il tag `latest` viene sovrascritto ad ogni push. Per un riferimento immutabile, taggare anche con lo short SHA del commit:
```bash
docker build -t ghcr.io/frapanca/habit-tracker-backend:$(git rev-parse --short HEAD) ./backend
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

### Kubernetes

Deploy alternativo su Kubernetes (validato su un cluster locale minikube), parallelo a Docker Compose: stesse immagini, stessa applicazione, orchestrazione diversa. I manifest vivono in `k8s/`.

#### Oggetti

| Oggetto | Nome | Note |
|---|---|---|
| `Namespace` | `habit-tracker` | isola tutte le risorse del progetto |
| `ConfigMap` | `habit-tracker-config` | `NODE_ENV`, `PORT`, `MONGO_DB_NAME` (dato non sensibile) |
| `Secret` | `habit-tracker-db-secret` | `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD` (dato sensibile) |
| `PersistentVolumeClaim` | `mongodb-pvc` | 500Mi, `ReadWriteOnce`, montata su `/data/db` |
| `Deployment` + `Service` | `mongodb` | 1 replica, `strategy: Recreate` (coerente con un volume `ReadWriteOnce`) |
| `Deployment` + `Service` | `backend` | 2 repliche |
| `Deployment` + `Service` | `frontend` | 1 replica |
| `Ingress` | `habit-tracker-ingress` | host `habit-tracker.local`, instrada tutto verso `frontend` |
| `NetworkPolicy` × 3 | - | limita il traffico in ingresso di ciascun livello (dettagli sotto) |

#### Rete interna

I `Service` sono `ClusterIP` (nessuna esposizione diretta) e usano gli stessi nomi già usati in Docker Compose (`mongodb`, `backend`, `frontend`). Il DNS interno del cluster risolve quei nomi esattamente come faceva la rete Compose: nessuna modifica al codice applicativo o a `nginx.conf` è stata necessaria per il porting.

#### Ingress e nginx: due livelli distinti

Il controller Ingress (ingress-nginx) instrada **tutto** il traffico verso il `Service` `frontend`, senza suddividere `/api` a livello di Ingress. Lo split verso il backend resta interamente a carico del nginx *dentro* il container frontend (lo stesso `nginx.conf` già documentato in [`frontend/README.md`](frontend/README.md)), esattamente come nella rete Compose, solo con un livello di accesso esterno in più davanti.

#### ConfigMap e Secret: differenza rispetto a Compose

Docker Compose interpola `${VAR}` nel proprio file `.env` al momento di `docker compose up`. Kubernetes non ha un equivalente diretto: i valori di `ConfigMap`/`Secret` vengono passati ai container così come sono, senza sostituzione di riferimenti al loro interno. Per comporre `MONGO_URI` (che nel `docker-compose.yml` risultava già interpolata da Compose) il Deployment del backend usa la sintassi nativa di Kubernetes per variabili dipendenti:
```yaml
env:
  - name: MONGO_USER
    valueFrom: { secretKeyRef: { name: habit-tracker-db-secret, key: MONGO_INITDB_ROOT_USERNAME } }
  - name: MONGO_PASSWORD
    valueFrom: { secretKeyRef: { name: habit-tracker-db-secret, key: MONGO_INITDB_ROOT_PASSWORD } }
  - name: MONGO_URI
    value: "mongodb://$(MONGO_USER):$(MONGO_PASSWORD)@mongodb:27017/$(MONGO_DB_NAME)?authSource=admin"
```
`$(...)` referenzia variabili già definite più in alto nello stesso container; nessuna credenziale in chiaro finisce nel `ConfigMap`.

#### NetworkPolicy

Tre policy restringono il traffico in ingresso: `mongodb` accetta solo dal `backend` (27017), `backend` solo dal `frontend` (5000), `frontend` solo dal namespace `ingress-nginx` (80). Di default in Kubernetes tutto il traffico tra pod è permesso; una `NetworkPolicy` lo restringe solo se il CNI del cluster la applica.

#### minikube: cosa rifare ad ogni avvio

Solo la prima volta (o dopo `minikube delete`):
```bash
minikube start --cni=calico
minikube addons enable ingress
minikube image load habit-tracker-backend:latest
minikube image load habit-tracker-frontend:latest
```
Ad ogni riavvio del PC, se non è stato fatto `minikube delete`, basta:
```bash
minikube start
```
CNI, addon e immagini restano nel container che ospita il cluster.

#### Setup e avvio rapido (Kubernetes)

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/
kubectl get pods -n habit-tracker -w    # attendere che tutto sia Running/Ready

# risolvere l'hostname usato dall'Ingress
echo "$(minikube ip)  habit-tracker.local" | sudo tee -a /etc/hosts
```
App disponibile su `http://habit-tracker.local`.

#### Comandi utili

```bash
kubectl get all -n habit-tracker             # panoramica di tutte le risorse
kubectl get ingress -n habit-tracker         # verifica host/address dell'Ingress
kubectl logs -f deployment/backend -n habit-tracker
kubectl rollout restart deployment/backend -n habit-tracker   # dopo un'immagine aggiornata
minikube image ls | grep habit-tracker       # conferma che le immagini siano visibili al cluster
```

#### Note tecniche

Le stesse immagini Docker (`habit-tracker-backend`, `habit-tracker-frontend`) girano su Kubernetes senza nessuna modifica: nessun rebuild specifico per K8s è stato necessario, solo `minikube image load` per renderle visibili al Docker daemon *interno* al nodo minikube, distinto dal Docker daemon dell'host. Per questo `docker images` sull'host non basta a garantire che un pod possa avviarsi (`imagePullPolicy: Never` cerca solo nel daemon del nodo).

### Helm

Deploy alternativo su Kubernetes, parametrico invece che statico: stessa applicazione, stessi oggetti già visti in `k8s/` (tenuti nel repo come riferimento), impacchettati in un chart Helm sotto `charts/habit-tracker/` con l'aggiunta del pezzo mancante rispetto ai manifest raw: l'**Horizontal Pod Autoscaler**.

#### Cosa cambia rispetto ai manifest raw

| Aspetto | `k8s/` (raw) | `charts/habit-tracker/` (Helm) |
|---|---|---|
| Parametrizzazione | valori hardcoded nei file | tutto in `values.yaml`, override via `-f`/`--set` |
| Autoscaling | assente | `HorizontalPodAutoscaler` per il backend (CPU 70%), opzionale anche per il frontend |
| Namespace | creato da `00-namespace.yaml` | **non** creato dal chart di default (dettagli sotto) |
| Secret MongoDB | file `.example` da copiare a mano | due modalità supportate, descritte sotto |
| Rollback | nessuno nativo | `helm rollback` sullo storico release |

#### Namespace: perché non lo crea il chart

Se il chart creasse il proprio `Namespace`, un `helm uninstall` lo cancellerebbe insieme a tutto ciò che contiene, anche risorse non gestite da questa release. Il flag `namespace.create` in `values.yaml` resta `false` di default; il namespace va creato a parte:
```bash
kubectl create namespace habit-tracker
```
(oppure con `helm install ... --namespace habit-tracker --create-namespace`, che lo gestisce fuori dal ciclo di vita della release).

#### Secret MongoDB: due modalità

`mongodb.auth.existingSecret` in `values.yaml` sceglie tra:
1. **Secret esterno già esistente** (consigliato per un uso reale): il `Secret` viene creato separatamente, il chart si limita a referenziarlo per nome.
2. **Generato dal chart**: valori passati con un file non versionato, copiando il template:
```bash
cp charts/habit-tracker/values-secret.yaml.example charts/habit-tracker/values-secret.yaml
# poi modifica username/password
```
`values-secret.yaml` è già in `.gitignore`. Se non fornisci credenziali in nessuna delle due modalità, `helm install` fallisce subito con un errore leggibile (`required`) invece di far partire un pod in `CrashLoopBackOff`.

#### Vincolo nascosto: nome del Service backend

Il `Service` del backend si chiama `backend`, non `habit-tracker-backend` come le altre risorse: `frontend/nginx.conf` ha `proxy_pass http://backend:5000` incorporato nell'immagine Docker in fase di build, non è un template runtime. Cambiare quel nome romperebbe il proxy del frontend finché non si ribuilda l'immagine con un `nginx.conf` aggiornato (`backend.serviceName` in `values.yaml`, documentato lì).

#### Setup e avvio rapido (Helm)

```bash
minikube addons enable ingress
minikube addons enable metrics-server   # necessario per l'HPA

eval $(minikube docker-env)
docker build -t habit-tracker-backend:dev  ./backend
docker build -t habit-tracker-frontend:dev ./frontend

kubectl create namespace habit-tracker

helm install habit-tracker ./charts/habit-tracker \
  --namespace habit-tracker \
  -f charts/habit-tracker/values-dev.yaml \
  -f charts/habit-tracker/values-secret.yaml

kubectl get pods -n habit-tracker -w    # attendere che tutto sia Running/Ready

echo "$(minikube ip)  habit-tracker.local" | sudo tee -a /etc/hosts
```
App disponibile su `http://habit-tracker.local`. L'output di `helm install`/`upgrade` stampa un `NOTES.txt` contestuale ai valori usati (host Ingress, se l'HPA è attivo, come disinstallare).

#### Comandi utili

```bash
helm lint ./charts/habit-tracker                          # valida sintassi e struttura del chart
helm template habit-tracker ./charts/habit-tracker \
  -f charts/habit-tracker/values-dev.yaml \
  -f charts/habit-tracker/values-secret.yaml               # mostra i manifest renderizzati, senza deployare

helm upgrade habit-tracker ./charts/habit-tracker \
  --namespace habit-tracker \
  -f charts/habit-tracker/values-dev.yaml \
  -f charts/habit-tracker/values-secret.yaml               # applica modifiche a values/template

helm history habit-tracker -n habit-tracker                # storico delle release
helm rollback habit-tracker 1 -n habit-tracker             # torna a una revisione precedente

helm uninstall habit-tracker -n habit-tracker              # rimuove la release (il Namespace resta, vedi sopra)
```

---

## English

### Description

A minimal app for logging daily habits (e.g. "Drink 2L of water") and marking them done day by day. The React frontend talks to a Node/Express REST backend, which persists data to MongoDB.

The focus of this project is containerization and orchestration: multi-stage Dockerfiles, network/secrets/persistence management across the three services, orchestrated with Docker Compose and, alternatively, with Kubernetes and a Helm chart that parametrizes the deployment and adds autoscaling.

### Tech stack

- **Frontend**: React 19, Vite, served in production by nginx
- **Backend**: Node.js 20, Express, Mongoose
- **Database**: MongoDB 7
- **Testing**: Vitest (frontend and backend), Supertest, mongodb-memory-server, React Testing Library
- **Containerization**: Docker, Docker Compose
- **Orchestration**: Kubernetes (raw manifests in `k8s/`) and Helm (chart in `charts/habit-tracker/`), both validated on a local minikube cluster

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
├── frontend/                    # details in frontend/README.md
│   ├── Dockerfile                 # multi-stage: build (Node) → test → production (nginx)
│   ├── .dockerignore
│   ├── .env                       # optional local override (VITE_API_BASE_URL)
│   ├── .gitignore
│   ├── .oxlintrc.json              # linter configuration (oxlint)
│   ├── nginx.conf                  # reverse proxy /api/ → backend:5000
│   ├── src/
│   │   ├── App.jsx
│   │   ├── App.css
│   │   └── api.js                  # fetch wrapper, relative base URL by default
│   └── tests/
│       ├── setup.js                # import '@testing-library/jest-dom'
│       └── unit/
│           └── App.test.jsx
│
├── k8s/                         # raw Kubernetes manifests, kept as reference (see charts/ for the Helm deploy)
│   ├── 00-namespace.yaml
│   ├── 01-configmap.yaml         # NODE_ENV, PORT, MONGO_DB_NAME (non-sensitive data)
│   ├── 02-secret.yaml            # MongoDB credentials (sensitive data)
│   ├── 03-mongodb.yaml           # PVC + Deployment (1 replica) + Service
│   ├── 04-backend.yaml           # Deployment (2 replicas) + Service
│   ├── 05-frontend.yaml          # Deployment + Service
│   ├── 06-ingress.yaml           # routes everything to frontend
│   └── 07-networkpolicy.yaml     # isolates traffic between the three tiers
│
└── charts/habit-tracker/        # Helm deploy, details in the "Helm" section below
    ├── Chart.yaml
    ├── values.yaml                    # default values
    ├── values-dev.yaml                # overrides for local testing (minikube/kind)
    ├── values-secret.yaml.example     # Mongo credentials template, never commit the filled-in copy
    └── templates/
        ├── _helpers.tpl               # common labels + name resolution (secret, mongo service)
        ├── namespace.yaml             # optional, disabled by default
        ├── configmap.yaml
        ├── secret.yaml                # only generated if you're not using an existing external Secret
        ├── mongodb-pvc.yaml
        ├── mongodb-deployment.yaml
        ├── mongodb-service.yaml
        ├── backend-deployment.yaml
        ├── backend-service.yaml
        ├── backend-hpa.yaml           # Horizontal Pod Autoscaler
        ├── frontend-deployment.yaml
        ├── frontend-service.yaml
        ├── frontend-hpa.yaml          # disabled by default
        ├── ingress.yaml
        ├── networkpolicy.yaml
        └── NOTES.txt                  # post-install/upgrade instructions
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

#### Registry

The `backend` and `frontend` images are published to GitHub Container Registry, referenced in `docker-compose.yml` next to `build:`:

```yaml
backend:
  build: ./backend
  image: ghcr.io/frapanca/habit-tracker-backend:latest

frontend:
  build: ./frontend
  image: ghcr.io/frapanca/habit-tracker-frontend:latest
```

`mongodb` is excluded: it uses the official `mongo:7` image, never pushed.

Build and push are two separate commands:
```bash
docker compose build backend frontend
docker compose push backend frontend
```

Requires a prior login:
```bash
docker login ghcr.io -u <username>
```
(with a Personal Access Token scoped to `write:packages`, never a plaintext password)

The `latest` tag is overwritten on every push. For an immutable reference, also tag with the commit's short SHA:
```bash
docker build -t ghcr.io/frapanca/habit-tracker-backend:$(git rev-parse --short HEAD) ./backend
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

### Kubernetes

Alternative deployment on Kubernetes (validated on a local minikube cluster), parallel to Docker Compose: same images, same application, different orchestration. Manifests live in `k8s/`.

#### Objects

| Object | Name | Notes |
|---|---|---|
| `Namespace` | `habit-tracker` | isolates all project resources |
| `ConfigMap` | `habit-tracker-config` | `NODE_ENV`, `PORT`, `MONGO_DB_NAME` (non-sensitive data) |
| `Secret` | `habit-tracker-db-secret` | `MONGO_INITDB_ROOT_USERNAME`, `MONGO_INITDB_ROOT_PASSWORD` (sensitive data) |
| `PersistentVolumeClaim` | `mongodb-pvc` | 500Mi, `ReadWriteOnce`, mounted at `/data/db` |
| `Deployment` + `Service` | `mongodb` | 1 replica, `strategy: Recreate` (consistent with a `ReadWriteOnce` volume) |
| `Deployment` + `Service` | `backend` | 2 replicas |
| `Deployment` + `Service` | `frontend` | 1 replica |
| `Ingress` | `habit-tracker-ingress` | host `habit-tracker.local`, routes everything to `frontend` |
| `NetworkPolicy` × 3 | - | restricts inbound traffic for each tier (see below) |

#### Internal networking

`Service` objects are `ClusterIP` (no direct exposure) and use the same names already used in Docker Compose (`mongodb`, `backend`, `frontend`). The cluster's internal DNS resolves those names exactly like the Compose network did: no changes to application code or `nginx.conf` were needed for the port.

#### Ingress and nginx: two distinct layers

The Ingress controller (ingress-nginx) routes **all** traffic to the `frontend` `Service`, without splitting `/api` at the Ingress level. The split toward the backend stays entirely inside the frontend container's own nginx (the same `nginx.conf` already documented in [`frontend/README.md`](frontend/README.md)), exactly as on the Compose network, just with one extra external access layer in front.

#### ConfigMap and Secret: difference from Compose

Docker Compose interpolates `${VAR}` in its own `.env` file at `docker compose up` time. Kubernetes has no direct equivalent: `ConfigMap`/`Secret` values are passed to containers as-is, with no substitution of references inside them. To compose `MONGO_URI` (already interpolated by Compose in `docker-compose.yml`), the backend Deployment uses Kubernetes' native syntax for dependent environment variables:
```yaml
env:
  - name: MONGO_USER
    valueFrom: { secretKeyRef: { name: habit-tracker-db-secret, key: MONGO_INITDB_ROOT_USERNAME } }
  - name: MONGO_PASSWORD
    valueFrom: { secretKeyRef: { name: habit-tracker-db-secret, key: MONGO_INITDB_ROOT_PASSWORD } }
  - name: MONGO_URI
    value: "mongodb://$(MONGO_USER):$(MONGO_PASSWORD)@mongodb:27017/$(MONGO_DB_NAME)?authSource=admin"
```
`$(...)` references variables already defined earlier in the same container; no credential in plain text ever lands in the `ConfigMap`.

#### NetworkPolicy

Three policies restrict inbound traffic: `mongodb` accepts only from `backend` (27017), `backend` only from `frontend` (5000), `frontend` only from the `ingress-nginx` namespace (80). By default, all pod-to-pod traffic is allowed in Kubernetes; a `NetworkPolicy` restricts it only if the cluster's CNI enforces it.

#### minikube: what needs redoing on every boot

Only the first time (or after `minikube delete`):
```bash
minikube start --cni=calico
minikube addons enable ingress
minikube image load habit-tracker-backend:latest
minikube image load habit-tracker-frontend:latest
```
On every subsequent reboot, as long as `minikube delete` wasn't run:
```bash
minikube start
```
CNI, addons and images persist inside the container hosting the cluster.

#### Quick setup (Kubernetes)

```bash
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/
kubectl get pods -n habit-tracker -w    # wait until everything is Running/Ready

# resolve the hostname used by the Ingress
echo "$(minikube ip)  habit-tracker.local" | sudo tee -a /etc/hosts
```
App available at `http://habit-tracker.local`.

#### Useful commands

```bash
kubectl get all -n habit-tracker             # overview of all resources
kubectl get ingress -n habit-tracker         # check the Ingress host/address
kubectl logs -f deployment/backend -n habit-tracker
kubectl rollout restart deployment/backend -n habit-tracker   # after an updated image
minikube image ls | grep habit-tracker       # confirm the images are visible to the cluster
```

#### Technical notes

The same Docker images (`habit-tracker-backend`, `habit-tracker-frontend`) run on Kubernetes with no modification at all: no K8s-specific rebuild was needed, only `minikube image load` to make them visible to the Docker daemon *inside* the minikube node, distinct from the host's Docker daemon. That's why `docker images` on the host alone doesn't guarantee a pod can start (`imagePullPolicy: Never` only looks in the node's own daemon).

### Helm

Alternative deployment on Kubernetes, parametric instead of static: same application, same objects already seen under `k8s/` (kept in the repo as a reference), packaged as a Helm chart under `charts/habit-tracker/` with the piece missing from the raw manifests added on top: the **Horizontal Pod Autoscaler**.

#### What changes compared to the raw manifests

| Aspect | `k8s/` (raw) | `charts/habit-tracker/` (Helm) |
|---|---|---|
| Parametrization | hardcoded values in the files | everything in `values.yaml`, overridable via `-f`/`--set` |
| Autoscaling | none | `HorizontalPodAutoscaler` for the backend (CPU 70%), optionally for the frontend too |
| Namespace | created by `00-namespace.yaml` | **not** created by the chart by default (see below) |
| MongoDB Secret | `.example` file to copy by hand | two supported modes, see below |
| Rollback | none built in | `helm rollback` over the release history |

#### Namespace: why the chart doesn't create it

If the chart created its own `Namespace`, a `helm uninstall` would delete it along with everything it contains, including resources not managed by this release. The `namespace.create` flag in `values.yaml` stays `false` by default; the namespace needs to be created separately:
```bash
kubectl create namespace habit-tracker
```
(or with `helm install ... --namespace habit-tracker --create-namespace`, which keeps it outside the release's lifecycle).

#### MongoDB Secret: two modes

`mongodb.auth.existingSecret` in `values.yaml` picks between:
1. **An already-existing external Secret** (recommended for real use): you create the `Secret` separately, the chart just references it by name.
2. **Generated by the chart**: values passed via a file that's never committed, by copying the template:
```bash
cp charts/habit-tracker/values-secret.yaml.example charts/habit-tracker/values-secret.yaml
# then edit username/password
```
`values-secret.yaml` is already in `.gitignore`. If you don't provide credentials through either mode, `helm install` fails immediately with a readable `required` error instead of a pod stuck in `CrashLoopBackOff`.

#### A hidden constraint: the backend Service name

The backend `Service` is named `backend`, not `habit-tracker-backend` like the other resources: `frontend/nginx.conf` has `proxy_pass http://backend:5000` baked into the Docker image at build time, not a runtime template. Changing that name would break the frontend's proxy until the image is rebuilt with an updated `nginx.conf` (`backend.serviceName` in `values.yaml`, documented there).

#### Quick setup (Helm)

```bash
minikube addons enable ingress
minikube addons enable metrics-server   # required for the HPA

eval $(minikube docker-env)
docker build -t habit-tracker-backend:dev  ./backend
docker build -t habit-tracker-frontend:dev ./frontend

kubectl create namespace habit-tracker

helm install habit-tracker ./charts/habit-tracker \
  --namespace habit-tracker \
  -f charts/habit-tracker/values-dev.yaml \
  -f charts/habit-tracker/values-secret.yaml

kubectl get pods -n habit-tracker -w    # wait until everything is Running/Ready

echo "$(minikube ip)  habit-tracker.local" | sudo tee -a /etc/hosts
```
App available at `http://habit-tracker.local`. The `helm install`/`upgrade` output prints a `NOTES.txt` message contextual to the values used (Ingress host, whether the HPA is on, how to uninstall).

#### Useful commands

```bash
helm lint ./charts/habit-tracker                          # validates the chart's syntax and structure
helm template habit-tracker ./charts/habit-tracker \
  -f charts/habit-tracker/values-dev.yaml \
  -f charts/habit-tracker/values-secret.yaml               # shows the rendered manifests, without deploying

helm upgrade habit-tracker ./charts/habit-tracker \
  --namespace habit-tracker \
  -f charts/habit-tracker/values-dev.yaml \
  -f charts/habit-tracker/values-secret.yaml               # applies changes to values/templates

helm history habit-tracker -n habit-tracker                # release history
helm rollback habit-tracker 1 -n habit-tracker             # roll back to a previous revision

helm uninstall habit-tracker -n habit-tracker              # removes the release (the Namespace stays, see above)
```