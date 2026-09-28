# Habit Tracker

Applicazione a 3 livelli (React + Node/Express + MongoDB) per il tracciamento di abitudini quotidiane.

*Progetto didattico con focus sulle tecnologie DevOps*

## Italiano

### Descrizione

Un'app minimale per registrare abitudini giornaliere (es. "Bere 2L d'acqua") e segnarle come completate giorno per giorno. Il frontend React comunica con un backend REST Node/Express, che persiste i dati su MongoDB.

Il focus del progetto è la containerizzazione e l'orchestrazione: Dockerfile multi-stage, gestione di rete, segreti e persistenza tra i tre servizi, orchestrati con Docker Compose e, in alternativa, con Kubernetes e con un chart Helm che ne parametrizza il deploy e aggiunge l'autoscaling, con una pipeline CI/CD che ne automatizza test e rilascio delle immagini. Lo stesso stack Docker può inoltre essere provisionato in modo dichiarativo con Terraform, sia in locale (`terraform-docker/`) sia su AWS con un'infrastruttura di produzione end-to-end (EC2, Secrets Manager, IAM) in `terraform-aws/`, con un registry Docker e i permessi CI condivisi tra i deploy AWS in `terraform-aws-shared/`. Lo stesso Helm chart usato su minikube può infine essere deployato su un cluster Kubernetes gestito reale (Amazon EKS), provisionato anch'esso con Terraform, in `terraform-aws-eks/`.

L'applicazione è osservabile con due approcci complementari: le metriche (Prometheus, Alertmanager, Grafana) dicono *cosa* sta succedendo, i log centralizzati con lo stack ELK (Filebeat, Logstash, Elasticsearch, Kibana) aiutano a capire *perché*. Il backend produce log strutturati in JSON, nginx scrive l'access log su file, e una pipeline dedicata li raccoglie, li normalizza e li rende consultabili in una dashboard Kibana versionata nel repository.

Il lavoro di sviluppo è tracciato su una board Kanban Jira collegata a questa repository tramite l'app "GitHub for Atlassian": i commit possono referenziare le issue Jira (es. HTKB-1 #done) e aggiornarne automaticamente lo stato tramite Smart Commits.

### Stack tecnologico

- **Frontend**: React 19, Vite, servito in produzione da nginx
- **Backend**: Node.js 20, Express, Mongoose
- **Database**: MongoDB 7
- **Test**: Vitest (frontend e backend), Supertest, mongodb-memory-server, React Testing Library
- **Containerizzazione**: Docker, Docker Compose
- **Orchestrazione**: Kubernetes (manifest raw in `k8s/`) e Helm (chart in `charts/habit-tracker/`), entrambi validati su un cluster locale minikube
- **Infrastructure as Code**: Terraform, provider `kreuzwerker/docker` per lo stack locale (`terraform-docker/`), provider `hashicorp/aws` per il deploy in produzione su EC2 (`terraform-aws/`), per un cluster Amazon EKS (`terraform-aws-eks/`) e per le risorse condivise tra i due (`terraform-aws-shared/`)
- **Monitoring**: Prometheus, Alertmanager, Grafana (dashboard as code), cAdvisor, mongodb-exporter; metriche applicative con `prom-client`
- **Logging**: log strutturati JSON con Winston, stack ELK (Filebeat, Logstash, Elasticsearch, Kibana) per raccolta, parsing e visualizzazione

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

Il flusso dei log di backend e nginx verso lo stack ELK è descritto nella sezione [Logging centralizzato](#logging-centralizzato-stack-elk).

### Struttura del repository

```
habit-tracker/
├── README.md                    # questo file
├── docker-compose.yml           # orchestrazione locale dei 3 servizi (mongodb, backend, frontend)
├── docker-compose.aws.yml       # orchestrazione per il deploy su EC2 (immagini da ECR)
├── docker-compose.monitoring.yml # stack di monitoring (add-on): Prometheus, Alertmanager, Grafana, exporter
├── docker-compose.logging.yml   # stack di logging centralizzato (add-on): Filebeat, Logstash, Elasticsearch, Kibana
├── elk/                         # configurazione dello stack di logging (dettagli nella sezione Logging qui sotto)
│   ├── filebeat/
│   │   └── filebeat.yml           # input sui volumi di log, output verso Logstash
│   ├── logstash/
│   │   └── pipeline/
│   │       └── logstash.conf      # filtri: json (backend), grok + drop healthcheck (nginx), output verso Elasticsearch
│   └── kibana/
│       └── habit-tracker-dashboard.ndjson  # dashboard esportata, importabile via API
├── screenshots/
│   └── kibana-dashboard.png     # immagine della dashboard Kibana usata in questo README
├── monitoring/                  # configurazione e strumenti del monitoring (dettagli nella sezione Monitoring qui sotto)
│   ├── prometheus/               # prometheus.yml, recording rules, alerting rules, unit test promtool
│   ├── alertmanager/              # routing, receiver, inhibit rules
│   ├── alert-receiver/            # webhook locale che logga le notifiche
│   ├── grafana/                   # datasource e dashboard provisionate da file
│   └── scripts/                   # load-test.sh (traffico) e chaos.sh (simulazione guasti)
├── .env.example                 # template variabili lette da Compose (credenziali Mongo, versione stack ELK)
├── .gitignore
├── package.json                 # script aggregatore: lancia i test di backend + frontend
│
├── backend/                     # dettagli in backend/README.md
│   ├── Dockerfile                # multi-stage: build → test → production
│   ├── .dockerignore
│   ├── .env                      # solo per esecuzione locale fuori Docker
│   ├── src/
│   │   ├── app.js                # app Express (senza side-effect, importabile nei test): metriche, request logging, route
│   │   ├── server.js             # entry point reale: connectDB() + app.listen()
│   │   ├── db.js                 # connessione MongoDB
│   │   ├── logger.js             # logger Winston: JSON su file (volume backend-logs) e su stdout
│   │   ├── metrics.js            # metriche Prometheus (prom-client) e middleware
│   │   ├── models/
│   │   │   ├── Habit.js
│   │   │   └── Entry.js
│   │   └── routes/
│   │       └── habitsRoute.js
│   └── tests/
│       ├── setup.js              # MongoDB in-memory condiviso tra i test
│       ├── unit/                 # test sui modelli, isolati
│       └── integration/          # test sulle route HTTP e sulle metriche (Supertest)
│
├── frontend/                    # dettagli in frontend/README.md
│   ├── Dockerfile                 # multi-stage: build (Node) → test → production (nginx)
│   ├── .dockerignore
│   ├── .env                       # override locale opzionale (VITE_API_BASE_URL)
│   ├── .gitignore
│   ├── .oxlintrc.json              # configurazione linter (oxlint)
│   ├── nginx.conf                  # reverse proxy /api/ → backend:5000 + access log su file (formato combined)
│   ├── src/
│   │   ├── App.jsx
│   │   ├── App.css
│   │   └── api.js                  # wrapper fetch, base URL relativa di default
│   └── tests/
│       ├── setup.js                # import '@testing-library/jest-dom'
│       └── unit/
│           └── App.test.jsx
│
├── terraform-docker/               # dettagli nella sezione "Terraform - Docker locale" sotto
│   ├── main.tf                     # provider, reti, volume, immagini, container
│   ├── variables.tf                # variabili con default e validazioni
│   ├── outputs.tf                  # id/nomi delle risorse create + URL di accesso
│   ├── terraform.tfvars.example    # template di valori (nessun segreto reale)
│   ├── .terraform.lock.hcl         # Terraform lock file
│   └── .gitignore                  # esclude state, .terraform/, *.tfvars reali
│
├── terraform-aws-shared/            # dettagli nella sezione "Terraform - Shared" sotto
│   ├── providers.tf
│   ├── variables.tf
│   ├── ecr.tf                       # repository ECR + lifecycle policy
│   ├── github-oidc.tf               # provider OIDC GitHub + ruolo per il push della CD
│   └── outputs.tf
│
├── terraform-aws/                  # dettagli nella sezione "Terraform - AWS" sotto
│   ├── providers.tf
│   ├── variables.tf
│   ├── network.tf                  # data source su VPC/subnet di default
│   ├── security.tf                 # security group
│   ├── iam.tf                      # role + instance profile
│   ├── secrets.tf                  # secret Mongo + random_password
│   ├── s3.tf                       # bucket dei backup MongoDB + lifecycle
│   ├── ec2.tf                      # key pair + istanza + user_data
│   ├── outputs.tf
│   ├── terraform.tfvars            # non committato: IP SSH, chiave pubblica, tag immagini
│   └── templates/
│       └── user_data.sh.tpl        # bootstrap eseguito al primo avvio dell'EC2
│
├── terraform-aws-eks/               # dettagli nella sezione "Kubernetes su AWS (EKS)" sotto
│   ├── providers.tf
│   ├── variables.tf
│   ├── network.tf                   # tag delle subnet richiesti da EKS
│   ├── iam.tf                       # ruoli per cluster e node group
│   ├── eks.tf                       # cluster, access entry, node group, IRSA per l'EBS CSI driver
│   ├── kubernetes.tf                # provider kubernetes/helm, ingress-nginx, metrics-server, StorageClass
│   ├── argocd.tf                    # installa ArgoCD via Helm, gestito da Terraform
│   ├── outputs.tf
│   ├── terraform.tfvars             # non committato: node_desired_size, ecc.
│   └── terraform.tfvars.example
│
├── argocd/                      # dettagli nella sezione "GitOps con ArgoCD" sotto
│   └── application.yaml         # Application che sincronizza charts/habit-tracker da questo repository
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
    ├── values-eks.yaml                # override per il deploy su EKS (immagini da ECR, secret Mongo esterno per il flusso GitOps)
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

Monitoring e logging centralizzato non sono nel file principale: sono add-on in file Compose separati, da sovrapporre a `docker-compose.yml` quando servono (vedi [Stack opzionali](#stack-opzionali-add-on)).

#### Immagini e multi-stage build

Sia `backend/Dockerfile` che `frontend/Dockerfile` sono strutturati in **quattro stage**, e il contesto di build è la **root del repository** (non più le singole sottocartelle): necessario perché il progetto usa npm workspaces con un unico `package-lock.json` condiviso.

| Stage | Scopo | Finisce nell'immagine finale? |
|---|---|---|
| `deps` | Installa le dipendenze dell'intero workspace (root + backend + frontend) | No |
| `build` | Eredita da `deps`, aggiunge il codice sorgente del servizio | No |
| `test` | Eredita da `build`, esegue la suite di test (`npm run test`) | No |
| `production` | Immagine finale, solo quanto necessario per l'esecuzione | Sì |

Lo stage `test` **è** referenziato da `production` tramite `COPY --from=test <file innocuo>`: è un gate esplicito che forza Docker a costruirlo (ed eseguirlo) come prerequisito: se `npm run test` fallisce, l'intera build dell'immagine si interrompe prima di produrre `production`. Per eseguire solo lo stage di test in isolamento:
```bash
docker build --target test -t habit-tracker-backend-test -f backend/Dockerfile .
```

**Backend**: lo stage `deps` usa `node:20.19`. Con gli npm workspaces, `npm ci` installa sempre l'intero albero del monorepo, incluse le devDependencies del frontend (rolldown, che richiede glibc, vedi sotto). Lo stage `production` usa `node:20.19-alpine`: `npm ci --omit=dev` esclude tutte le devDependencies del workspace, rolldown compreso. Lo stage `production` crea anche `/app/backend/logs` con proprietario `node`: il processo gira da non-root e deve poter scrivere il file di log, che con lo stack di logging attivo è montato su un volume condiviso con Filebeat.

**Frontend**: gli stage `deps`, `build` e `test` usano `node:20.19`. Lo stage `production` è `nginx:alpine`: nessun Node nell'immagine finale, solo i file statici compilati (`dist/`). Lo stage `production` crea anche `/var/log/app-logs/nginx`, dove nginx scrive l'access log (montato su un volume condiviso con Filebeat quando lo stack di logging è attivo). Non serve un `chown`: il processo master di nginx gira come root e apre lui il file.

In entrambi i Dockerfile, i `package.json` (root + entrambi i workspace) vengono copiati e installati nello stage `deps` prima del codice sorgente: il layer delle dipendenze resta in cache quando cambia solo il codice.

#### Rete

Due reti Compose separate:
```yaml
networks:
  frontend-net:   # frontend ↔ backend
  backend-net:    # backend ↔ mongodb
```
Il servizio `backend` è l'unico presente su entrambe le reti. `frontend` e `mongodb` non hanno visibilità diretta l'uno sull'altro. Gli stack opzionali aggiungono le proprie reti (`monitoring-net`, `logging-net`) senza modificare queste.

#### Persistenza

```yaml
volumes:
  mongo-data:
```
Named volume montato su `/data/db` dentro il container `mongodb`. `docker compose down` preserva i dati; solo `docker compose down -v` li cancella. Lo stack di logging aggiunge i propri volumi (log, indici Elasticsearch), descritti nella sua sezione: con `down -v` vengono cancellati anche quelli.

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

Altre variabili:

- `IMAGE_TAG` (opzionale, default `v0.2.0`) sceglie il tag delle immagini `backend` e `frontend`, sia in lettura (`up`, `pull`) sia in scrittura (`build`, `push`).
- `NODE_ENV=production` è impostata nel servizio `backend` del compose: i log su stdout sono in JSON, coerenti con quelli scritti su file.
- `LOG_DIR` e `LOG_LEVEL` (opzionali) controllano la cartella e il livello minimo del logger del backend. Default: `backend/logs` e `info`.
- `ELASTIC_VERSION` (opzionale, default `9.4.6`) fissa la versione dei quattro componenti dello stack ELK: vedi la sezione sul logging centralizzato.

#### Healthcheck e ordine di avvio

`depends_on` con `condition: service_healthy` garantisce l'ordine:
```
mongodb (healthy) → backend (healthy) → frontend
```

| Servizio | Healthcheck |
|---|---|
| `mongodb` | `mongosh -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval "db.adminCommand('ping')"` |
| `backend` | `wget -qO- http://localhost:5000/api/health` |
| `frontend` | `wget -qO- http://127.0.0.1:80` |

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

#### Stack opzionali (add-on)

Monitoring e logging centralizzato vivono in file Compose separati, da sovrapporre al principale. L'applicazione non dipende da nessuno dei due e resta leggera quando non servono.

| File | Contenuto | Sezione |
|---|---|---|
| `docker-compose.yml` | Applicazione: `mongodb`, `backend`, `frontend` | questa |
| `docker-compose.monitoring.yml` | Prometheus, Alertmanager, Grafana, exporter | [Monitoring](#monitoring) |
| `docker-compose.logging.yml` | Filebeat, Logstash, Elasticsearch, Kibana | [Logging centralizzato](#logging-centralizzato-stack-elk) |

```bash
# applicazione + logging
docker compose -f docker-compose.yml -f docker-compose.logging.yml up -d

# applicazione + monitoring + logging
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml -f docker-compose.logging.yml up -d

# per non ripetere i -f (il separatore è ":" su Linux e macOS)
export COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml:docker-compose.logging.yml
docker compose up -d
```

I servizi definiti solo in un add-on (per esempio `filebeat`) sono visibili a `logs`, `ps` e `restart` soltanto se quel file è incluso: per fermare e ispezionare usa gli stessi file dell'avvio. Se avvii con un sottoinsieme dei file, Compose segnala come *orphan* i container degli altri stack già in esecuzione: è un avviso, e `--remove-orphans` li ferma e li rimuove.

#### Registry

Le immagini di `backend` e `frontend` sono pubblicate su GitHub Container Registry, referenziate nel `docker-compose.yml` accanto a `build:`. Il tag è parametrizzato con `IMAGE_TAG`, con default `v0.2.0`:

```yaml
backend:
  build:
    context: .
    dockerfile: backend/Dockerfile
  image: ghcr.io/frapanca/habit-tracker-backend:${IMAGE_TAG:-v0.2.0}

frontend:
  build:
    context: .
    dockerfile: frontend/Dockerfile
  image: ghcr.io/frapanca/habit-tracker-frontend:${IMAGE_TAG:-v0.2.0}
```

`mongodb` resta escluso: usa l'immagine ufficiale `mongo:7`, non va pushata. Lo stesso vale per i componenti degli stack opzionali, che usano immagini ufficiali.

Il tag identifica la versione dell'immagine: `docker compose build` la costruisce con quel nome e `docker compose push` la pubblica con lo stesso. Per lavorare su una versione diversa dal default:
```bash
IMAGE_TAG=<tag> docker compose build backend frontend
IMAGE_TAG=<tag> docker compose push backend frontend
```
(oppure `IMAGE_TAG=<tag>` nel `.env`). Il push manuale richiede un login preventivo:
```bash
docker login ghcr.io -u <username>
```
(con un Personal Access Token con permesso `write:packages`, mai una password in chiaro)

Le release pubblicate dalla CD (vedi [CI/CD](#cicd)) usano il tag Git della release e lo short SHA del commit: sono riferimenti immutabili, a differenza di un tag come `latest`, che verrebbe sovrascritto ad ogni push.

#### Note tecniche

**Vite/rolldown e Alpine**: la build del frontend fallisce su `node:20-alpine` con un errore relativo a `@rolldown/binding-linux-x64-musl` (binario nativo compilato per glibc, incompatibile con `musl`). Gli stage `deps`/`build`/`test` del frontend usano `node:20.19`; lo stage `production` resta `nginx:alpine`. Con gli npm workspaces questo vincolo si propaga anche allo stage `deps` del **backend**, che installa comunque le devDependencies del frontend: vedi la sezione "Immagini e multi-stage build" più sopra.

**Variabili `VITE_*`**: vengono sostituite in fase di build (`npm run build`), non lette a runtime nel browser. Il `.env` del frontend è escluso dal `.dockerignore` e non è presente durante la build in Docker. `api.js` usa `/api` come valore di default (`import.meta.env.VITE_API_BASE_URL || '/api'`).

**Dipendenze e lockfile**: le dipendenze del backend (compresa `winston`) sono dichiarate in `backend/package.json`, ma il lockfile è unico alla radice. Dopo ogni modifica alle dipendenze va rigenerato con `npm install` dalla root (per esempio `npm install winston -w backend`) e committato insieme al `package.json`: `npm ci` nei Dockerfile fallisce se i due file non sono sincronizzati.

**Log su file e permessi**: il backend gira come utente `node`, quindi la cartella dei log deve essere creata e assegnata a `node` nel Dockerfile prima dell'istruzione `USER`. Quando Docker monta per la prima volta un named volume su una cartella già esistente nell'immagine, ne eredita contenuto e permessi: per questo il volume `backend-logs` risulta scrivibile dal backend. nginx, che apre il file come root, non ha questo vincolo.

### Setup e avvio rapido

```bash
git clone <url-repo>
cd habit-tracker
cp .env.example .env   # e compilare MONGO_ROOT_PASSWORD

docker compose up --build
docker compose ps      # verificare che tutti i servizi siano "healthy"
```

App disponibile su `http://localhost`. Per aggiungere monitoring e logging centralizzato vedi [Stack opzionali](#stack-opzionali-add-on).

### Testing

Suite di test automatizzata su backend e frontend, lanciabile in un unico comando dalla root:
```bash
npm test
```
(equivalente a `npm run test:backend && npm run test:frontend`, si ferma al primo fallimento). Dettagli su framework, strategia di mock e copertura nei README di [`backend/`](backend/README.md#testing) e [`frontend/`](frontend/README.md#testing).

### CI/CD

Due workflow GitHub Actions distinti, con trigger diversi e scopi diversi:

| Workflow | File | Trigger | Scopo |
|---|---|---|---|
| CI | `.github/workflows/ci.yml` | push/PR verso `main` | Verifica continua ad ogni cambiamento: lint, test, audit di sicurezza, build |
| CD | `.github/workflows/cd.yml` | push di un tag `v*.*.*` | Build e pubblicazione delle immagini Docker su GHCR, solo per le release |

Un push generico su `main` fa scattare solo la CI; un tag di release fa scattare solo la CD. I due eventi Git (aggiornamento di branch vs creazione di tag) non si sovrappongono mai sullo stesso trigger.

#### CI

5 job, in sequenza/parallelo secondo le dipendenze (`needs`):

```
lint → test (matrix: Node 20, 22) ─┐
     → security (npm audit + Trivy) ┼→ build → ci-success
```

- **lint**: esegue il linter su tutto il progetto.
- **test**: matrice su due versioni di Node; il binario di `mongodb-memory-server` viene cachato tra le run (`actions/cache`) per evitare download ripetuti; la coverage viene caricata come artefatto solo per Node 20.
- **security**: `npm audit --audit-level=high` più una scansione filesystem con Trivy (CVE e secret leak), entrambe fallenti (`exit-code: 1`) se trovano problemi di severità alta/critica.
- **build**: build reale dell'applicazione, artefatto caricato per 5 giorni.
- **ci-success**: job "sentinella" che dipende da tutti gli altri, utile come singolo check obbligatorio da referenziare in una eventuale branch protection rule.

#### CD

```yaml
strategy:
  matrix:
    service: ['backend', 'frontend']
```

Un solo job, parametrizzato con una matrix su `service`: GitHub Actions lo esegue due volte in parallelo (una per `backend`, una per `frontend`), evitando di duplicare gli step per ciascun servizio.

Ad ogni esecuzione:
1. login a `ghcr.io` con `GITHUB_TOKEN` (nessun secret/PAT da gestire manualmente: il permesso `packages: write` dichiarato nel workflow è sufficiente, a patto che il repository abbia "Workflow permissions" impostato su *Read and write* in Settings → Actions → General)
2. login ad Amazon ECR assumendo un ruolo IAM tramite OIDC (nessuna chiave AWS statica salvata su GitHub, vedi "Terraform - Shared" più sotto)
3. build dell'immagine con **due tag**: il tag Git della release (`${{ github.ref_name }}`, es. `v1.0.0`) e lo short SHA del commit, per tracciabilità, applicati sia al riferimento GHCR sia a quello ECR
4. push di entrambi i tag verso entrambi i registry con `docker push --all-tags`

L'owner dell'immagine viene normalizzato in minuscolo (`${GITHUB_REPOSITORY_OWNER,,}`) perché i riferimenti Docker non ammettono maiuscole.

**Rilasciare una nuova versione:**
```bash
git tag v1.0.0
git push origin v1.0.0
```
Le immagini pubblicate su GHCR sono visibili su `https://github.com/<owner>?tab=packages`; quelle su ECR con `aws ecr describe-images --repository-name habit-tracker-backend`.

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
docker build -t habit-tracker-backend:dev  -f backend/Dockerfile .
docker build -t habit-tracker-frontend:dev -f frontend/Dockerfile .

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

### Terraform - Docker locale

Provisioning alternativo dello stesso stack Docker (mongodb + backend + frontend) tramite Infrastructure as Code, parallelo a Docker Compose: stesse immagini (backend/frontend da GHCR, mongodb da Docker Hub), stessa topologia di rete, ma dichiarata con risorse Terraform invece che con un file `docker-compose.yml`. I file vivono in `terraform-docker/`. Lo stack di logging ELK non è incluso in questo provisioning: resta specifico del Docker Compose.

#### Provider e versioni

| Componente | Versione |
|---|---|
| Terraform | `>= 1.5.0` |
| Provider `kreuzwerker/docker` | `~> 3.0` |

Il provider si connette al Docker daemon locale tramite il socket di default (`/var/run/docker.sock`).

#### Risorse gestite

| Risorsa Terraform | Nome | Scopo |
|---|---|---|
| `docker_network` | `backend_network`, `frontend_network` | Isolamento di rete, `backend` è l'unico servizio presente su entrambe |
| `docker_volume` | `mongo_volume` | Persistenza dei dati MongoDB (`mongo-data`) |
| `docker_image` | `mongodb-image`, `backend-image`, `frontend-image` | Immagini da Docker Hub (mongo) e da GHCR (backend/frontend) |
| `docker_container` | `mongodb`, `backend`, `frontend` | I tre servizi applicativi, con healthcheck, limiti di risorse e dipendenze |

La creazione segue l'ordine mongodb → backend → frontend, imposto con `depends_on`; ogni container attende che quello da cui dipende raggiunga lo stato `healthy` (`wait = true` + blocco `healthcheck`), riproducendo la semantica di `depends_on: condition: service_healthy` di Compose:
```hcl
resource "docker_container" "mongodb" {
  # ...
  wait = true
  healthcheck {
    test         = ["CMD-SHELL", "mongosh --quiet -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval \"db.adminCommand('ping')\" || exit 1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "20s"
  }
}
```

#### Variabili principali

| Nome | Descrizione | Default |
|---|---|---|
| `project_name` | Prefisso di progetto | `habit-tracker` |
| `github_user` | Owner GHCR delle immagini backend/frontend | `frapanca` |
| `backend`, `frontend` | Nomi/prefissi dei due servizi applicativi | `backend`, `frontend` |
| `github_image_tag_backend`, `github_image_tag_frontend` | Tag immagine da GHCR | `v0.1.1` |
| `backend_port` | Porta interna del backend | `5000` |
| `frontend_port` | Porta host mappata sulla 80 del frontend (validata tra 1025 e 65534) | `8080` |
| `db_name` | Nome/hostname del container MongoDB | `mongodb` |
| `mongo_image_name` | Nome immagine Docker Hub di MongoDB | `mongo` |
| `mongodb_version` | Tag immagine MongoDB | `7` |
| `mongo_root_username` | Utente root MongoDB | `admin` |
| `mongo_root_password` | Password root MongoDB (**sensitive**) | `CHANGE_ME` - da sovrascrivere |
| `mongo_root_database` | Nome del database applicativo | `habittracker` |

#### Output disponibili

| Output | Contenuto |
|---|---|
| `container_mongodb_id`, `container_backend_id`, `container_frontend_id` | ID Docker dei tre container |
| `container_mongodb_name`, `container_backend_name`, `container_frontend_name` | Nomi effettivi dei container |
| `network_backend_name`, `network_frontend_name` | Nomi delle reti Docker create |
| `volume_name`, `volume_path` | Nome e mountpoint del volume MongoDB |
| `access_url` | URL per raggiungere il frontend dall'host (`http://localhost:{frontend_port}`) |

#### Setup e avvio rapido (Terraform - Docker locale)

```bash
cd terraform-docker
cp terraform.tfvars.example terraform.tfvars   # e compilare mongo_root_password

terraform init
terraform plan
terraform apply

terraform output access_url    # URL per raggiungere il frontend
```

#### Comandi utili

```bash
terraform fmt -recursive                # normalizza la formattazione
terraform validate                      # controllo sintattico/statico
terraform output                        # mostra tutti gli output

terraform destroy                       # rimuove TUTTO, incluso il volume dati
docker ps -a                            # verifica che nessun container sia rimasto
docker network ls                       # verifica che le reti siano state rimosse
docker volume ls                        # verifica che il volume sia stato rimosso
```

#### Note tecniche

**Autenticazione GHCR**: se i pacchetti `backend`/`frontend` su GHCR sono privati, `terraform apply` fallisce nel pull a meno di autenticazione preventiva con `docker login ghcr.io`, oppure di un blocco `registry_auth` nel `provider "docker"` con token in variabile `sensitive`.

**`wait` + `healthcheck` al posto di `depends_on: condition`**: nel provider Docker, l'attesa dello stato *healthy* si dichiara sulla risorsa attesa (`wait = true` sul container da cui si dipende), non su chi dipende: a differenza della sintassi di Compose dove `condition: service_healthy` si scrive sul servizio dipendente.

**Healthcheck frontend, `localhost` vs `127.0.0.1`**: su `nginx:alpine` con `default.conf` personalizzato, lo script di init non abilita il listener IPv6; `wget http://localhost:80` può risolvere prima su `::1` e ricevere connessione rifiutata pur con nginx perfettamente funzionante su IPv4. L'healthcheck usa quindi `http://127.0.0.1:80` esplicito, per evitare l'ambiguità di risoluzione DNS.

**`terraform destroy` e il volume dati**: a differenza di `docker compose down` (che preserva i volumi finché non si aggiunge `-v`), `terraform destroy` rimuove *sempre* anche `docker_volume.mongo_volume`, dati compresi: non esiste una distinzione di default tra risorse "stato" e "dati persistenti". Per proteggere il volume da distruzioni accidentali si può aggiungere `lifecycle { prevent_destroy = true }` alla relativa risorsa.

**Segreti nello state**: `mongo_root_password` è marcata `sensitive = true` (nascosta negli output di plan/apply), ma resta comunque in chiaro nel file `terraform.tfstate` locale: accettabile per uso locale, da affrontare con state remoto cifrato o secret manager se il progetto evolve verso ambienti condivisi.

### Terraform - Shared

Risorse condivise tra i deploy EC2 (`terraform-aws/`) ed EKS (`terraform-aws-eks/`), in `terraform-aws-shared/`: un registry Docker e i permessi che la CD usa per pubblicarci le immagini. Tenute in un modulo a parte perché, a differenza di EC2 ed EKS, non ha senso distruggerle mai: sono gratuite da mantenere sempre attive, e la loro perdita romperebbe la pipeline CI/CD e svuoterebbe le immagini disponibili per entrambi i deploy.

#### Provider e versioni

| Componente | Versione |
|---|---|
| Terraform | `>= 1.5.0` |
| Provider `hashicorp/aws` | `~> 5.0` |
| Provider `hashicorp/tls` | `~> 4.0` |

#### Risorse gestite

| Risorsa Terraform | Nome | Scopo |
|---|---|---|
| `aws_ecr_repository` | `backend_ecr_repo`, `frontend_ecr_repo` | Registry immagini Docker, con scan automatico al push |
| `aws_ecr_lifecycle_policy` | uno per repository | Mantiene solo le ultime 5 immagini per repository |
| `aws_iam_openid_connect_provider` | provider GitHub Actions | Trust OIDC verso `token.actions.githubusercontent.com`, per credenziali AWS temporanee nella CD |
| `aws_iam_role` + policy attachment | ruolo push CD | Permesso di pubblicare immagini su ECR, assumibile solo dai workflow che girano per un push di tag su questo repository |

#### Perché è separato dagli altri moduli

Le immagini Docker e il permesso della CD di pubblicarle non dipendono da *dove* gira l'app (EC2 o EKS): sono infrastruttura di supporto condivisa. Tenerle in un modulo a parte, sempre applicato, evita due problemi concreti incontrati durante lo sviluppo di questo progetto: perdere le immagini ogni volta che si distrugge `terraform-aws/` per risparmiare sui costi, e dover ricreare da zero il ruolo OIDC (con conseguente aggiornamento della repository variable su GitHub) ogni volta. `terraform-aws/` e `terraform-aws-eks/` non referenziano queste risorse tramite Terraform (niente `terraform_remote_state`): sono root indipendenti, e ricostruiscono l'URL del registry a partire dall'account ID e dalla convenzione di naming.

#### Setup

```bash
cd terraform-aws-shared
terraform init
terraform apply
```

Nessun costo continuativo: repository ECR vuoti e un ruolo IAM non generano spesa, questo modulo può restare applicato indefinitamente.

#### Note tecniche

**Claim OIDC immutabile**: la condition `sub` della trust policy usa il formato `repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/tags/*`, introdotto da GitHub per i repository creati dopo il 15 luglio 2026 (vedi le variabili `github_owner_id`/`github_repository_id`). Un repository creato prima di quella data userebbe il formato precedente, solo nomi.

### Terraform - AWS

Provisioning dell'infrastruttura AWS per il deploy in produzione dell'applicazione, in `terraform-aws/`: le immagini backend/frontend (pubblicate su Amazon ECR, gestito separatamente in `terraform-aws-shared/`, vedi sotto) girano su un'istanza EC2 tramite Docker Compose, con le credenziali gestite da Secrets Manager invece che da variabili in chiaro.

#### Provider e versioni

| Componente | Versione |
|---|---|
| Terraform | `>= 1.5.0` |
| Provider `hashicorp/aws` | `~> 5.0` |
| Provider `hashicorp/random` | `~> 3.6` |

#### Risorse gestite

| Risorsa Terraform | Nome | Scopo |
|---|---|---|
| `random_password` + `aws_secretsmanager_secret` | credenziali Mongo | Generazione e storage delle credenziali root MongoDB, mai in chiaro nel repo |
| `aws_security_group` | `habit-tracker-sg` | Porta 80 aperta a tutti, porta 22 ristretta a un solo IP |
| `aws_iam_role` + `aws_iam_instance_profile` | ruolo EC2 | Permessi minimi: lettura del solo secret Mongo del progetto, pull da ECR |
| `aws_key_pair` | chiave SSH | Import della chiave pubblica locale per l'accesso SSH |
| `aws_instance` | istanza applicativa | Esegue Docker Compose con le immagini da ECR, bootstrap via `user_data` |

I repository ECR e il ruolo OIDC della CD non sono gestiti qui: vivono in `terraform-aws-shared/` (vedi sotto), applicato indipendentemente. L'URL delle immagini viene ricostruito in `ec2.tf` a partire da `data.aws_caller_identity.current.account_id` e dalla convenzione di naming (`<account>.dkr.ecr.<region>.amazonaws.com/habit-tracker-<servizio>:<tag>`), non tramite un riferimento diretto a una risorsa Terraform di questo modulo.

La VPC e le subnet utilizzate sono quelle di default dell'account (`data "aws_vpc"`, `data "aws_subnets"`), non create da questo progetto.

#### Variabili principali

| Nome | Descrizione | Default |
|---|---|---|
| `aws_region` | Regione AWS | `eu-west-1` |
| `project_name` | Prefisso di progetto | `habit-tracker` |
| `instance_type` | Tipo di istanza EC2 | `t3.micro` |
| `allowed_ssh_cidr` | CIDR autorizzato sulla porta 22 (formato `IP/32`) | nessuno, obbligatorio |
| `ssh_public_key_path` | Percorso della chiave pubblica SSH locale | nessuno, obbligatorio |
| `app_repo_url` | URL Git clonato dall'EC2 al boot | `https://github.com/FraPanca/Habit-Tracker.git` |
| `backend_image_tag`, `frontend_image_tag` | Tag delle immagini ECR da deployare | nessuno, obbligatorio |

#### Output disponibili

| Output | Contenuto |
|---|---|
| `mongo_secret_arn` | ARN del secret Mongo |
| `app_security_group_id` | ID del security group |
| `ec2_instance_profile_name` | Nome dell'instance profile IAM |
| `ec2_public_ip`, `app_url` | IP pubblico dell'istanza e URL per raggiungere l'app |

#### Come funziona il bootstrap

Al primo avvio (gestito da `cloud-init` tramite `user_data`, eseguito **una sola volta**), l'istanza:
1. installa Docker e il plugin Compose (non incluso nel repository di pacchetti di Amazon Linux 2023)
2. clona questo repository (pubblico, nessuna credenziale necessaria)
3. fa login a ECR con le credenziali temporanee del ruolo IAM assegnato all'istanza
4. recupera le credenziali Mongo da Secrets Manager e scrive un file `.env` nella cartella clonata
5. lancia `docker compose -f docker-compose.aws.yml up -d`, che riusa la stessa architettura a due reti del Compose locale ma con `backend`/`frontend` come `image:` da ECR invece che `build:`

Se aggiorni il codice su GitHub dopo che l'istanza è già attiva, l'EC2 non se ne accorge da sola: serve un redeploy (vedi comandi utili).

#### Setup e avvio rapido (Terraform - AWS)

```bash
cd terraform-aws
# creare terraform.tfvars con: allowed_ssh_cidr, ssh_public_key_path, backend_image_tag, frontend_image_tag

terraform init
terraform plan
terraform apply

terraform output app_url    # URL per raggiungere l'app
```

Build e push preventivo delle immagini su ECR (non gestito da Terraform):
```bash
aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-west-1.amazonaws.com

docker build -t habit-tracker-backend ./backend
docker tag habit-tracker-backend:latest <account-id>.dkr.ecr.eu-west-1.amazonaws.com/habit-tracker-backend:<tag>
docker push <account-id>.dkr.ecr.eu-west-1.amazonaws.com/habit-tracker-backend:<tag>
```
(stesso procedimento per `frontend`)

#### Comandi utili

```bash
terraform apply -replace="aws_instance.app"    # ricrea solo l'EC2 (es. dopo un push su GitHub), senza toccare il resto
terraform destroy                              # rimuove tutta l'infrastruttura AWS

aws ecr describe-images --repository-name habit-tracker-backend                          # lista immagini nel repo
aws ecr describe-image-scan-findings --repository-name habit-tracker-frontend \
  --image-id imageTag=<tag>                                                              # esito dello scanning di sicurezza

ssh -i ~/.ssh/habit-tracker-aws ec2-user@$(terraform output -raw ec2_public_ip)           # accesso SSH all'istanza
sudo docker compose -f /opt/app/docker-compose.aws.yml ps                                # stato dei container sull'EC2
sudo cat /var/log/cloud-init-output.log                                                  # log del bootstrap, utile per debug
```

#### Note tecniche

**Registry separato da GHCR**: questo deploy usa Amazon ECR, non GitHub Container Registry come il resto del progetto. È una scelta deliberata dell'esercizio (provisioning end-to-end con servizi nativi AWS), non un requisito tecnico: le immagini backend/frontend restano identiche, cambia solo dove vengono pubblicate.

**Docker Compose plugin su Amazon Linux 2023**: il pacchetto `docker` del repository di sistema AL2023 include solo il motore, non il plugin Compose v2. Lo script `user_data` lo scarica come binario da GitHub Releases e lo installa in `/usr/local/lib/docker/cli-plugins/`.

**`user_data` gira una sola volta**: a differenza di un deploy con pipeline CI/CD (vedi sopra, per GHCR), qui non c'è alcun meccanismo di auto-pull del codice o delle immagini dopo il primo boot. Un aggiornamento richiede o un accesso manuale via SSH (`git pull` + `docker compose up -d --pull always`) o la ricreazione dell'istanza con `terraform apply -replace`.

**Secret in Secrets Manager, non solo nello state**: la password generata da `random_password` viene scritta in Secrets Manager, da cui l'EC2 la legge a runtime senza credenziali statiche. Lo state Terraform contiene comunque il valore in chiaro (è una risorsa Terraform come le altre): la stessa avvertenza sul file di state locale vista per `terraform-docker/` si applica anche qui.

**Vulnerabilità nell'immagine base del frontend**: lo scanning ECR ha segnalato alcune CVE nel pacchetto di sistema `util-linux` incluso in `nginx:alpine`, tutte a vettore di attacco locale (richiedono una shell già attiva dentro il container). Il container frontend espone solo nginx, quindi il rischio pratico è considerato basso. Verificato l'11/09/2026, da ricontrollare ad ogni rebuild dell'immagine base.

**Costi**: ECR (500 MB-mese gratuiti nei primi 12 mesi dell'account, poi a pagamento), Secrets Manager (non incluso nel free tier, circa $0.40/mese per secret), EC2 t3.micro (idoneo al free tier nei primi 12 mesi dell'account). Eseguire `terraform destroy` a fine test per azzerare i costi.

### Kubernetes su AWS (EKS)

Deploy alternativo su un cluster Kubernetes reale su AWS, riusando lo stesso Helm chart già validato su minikube (`charts/habit-tracker/`), con un file di infrastruttura Terraform indipendente in `terraform-aws-eks/`.

#### Avviso di costo

A differenza di tutto il resto di questo progetto, **EKS non è gratuito nemmeno per pochi minuti di test**: il control plane costa circa $0.10/ora a prescindere dall'uso, a cui si sommano i nodi EC2 e l'eventuale load balancer. Da tenere acceso solo per il tempo necessario a testare, e distruggere subito dopo (vedi ordine di destroy sotto, importante).

#### Risorse gestite

| Risorsa | Scopo |
|---|---|
| `aws_iam_role` (cluster e nodi) | Ruoli richiesti da EKS per control plane e worker node |
| `aws_eks_cluster` | Control plane, sulle subnet della VPC di default |
| `aws_eks_access_entry` | Permessi Kubernetes per il principal che applica Terraform (API moderna, non la vecchia ConfigMap `aws-auth`) |
| `aws_eks_node_group` | Node group gestito, 2 istanze `t3.small` |
| `aws_iam_openid_connect_provider` (cluster) | OIDC del cluster stesso, per l'IRSA (IAM Roles for Service Accounts) |
| `aws_eks_addon` (aws-ebs-csi-driver) | Driver per la persistenza EBS, con ruolo IAM dedicato via IRSA |
| `kubernetes_storage_class` | StorageClass di default in `gp3` (l'add-on da solo non la crea, su un node group standard) |
| `helm_release` (ingress-nginx) | Stesso controller Ingress usato su minikube, qui con annotazione per un Network Load Balancer invece del Classic Load Balancer legacy di default |
| `helm_release` (metrics-server) | Richiesto dall'Horizontal Pod Autoscaler del chart |
| `helm_release` (argocd) | Installa ArgoCD nel cluster, usato per il deploy GitOps dell'applicazione (vedi la sezione "GitOps con ArgoCD" più sotto) |

#### `values-eks.yaml`

Override del chart per EKS: `backend.image.repository`/`frontend.image.repository` puntano al registry ECR completo invece del nome bare usato per le immagini locali di minikube, `pullPolicy: IfNotPresent` invece di `Never` (il nodo deve davvero scaricare l'immagine). Imposta anche `mongodb.auth.existingSecret`, usato dal flusso GitOps descritto più sotto per referenziare un Secret creato a mano nel cluster, invece di generarlo dal chart.

#### Setup e avvio rapido

```bash
cd terraform-aws-eks
terraform init
terraform apply    # 10-15 minuti, il cluster impiega tempo a diventare Active; include anche il bootstrap di ArgoCD
```

Da qui in poi il deploy dell'applicazione non avviene più con un `helm install` manuale, ma tramite ArgoCD: vedi la sezione "GitOps con ArgoCD" subito dopo per i passi completi (creazione del namespace e del secret Mongo, registrazione della Application, verifica del sync).

Test end-to-end una volta che l'app risulta sincronizzata (nessun dominio reale configurato, si passa l'header Host esplicitamente):
```bash
kubectl get svc -n ingress-nginx
curl -H "Host: habit-tracker.local" http://<hostname-nlb>
```

#### Destroy: ordine importante

A differenza degli altri moduli di questo progetto, qui l'ordine conta: l'applicazione è gestita da ArgoCD (a sua volta installato da Terraform), non più da un `helm install` diretto, e Terraform gestisce tre `helm_release` (ingress-nginx, metrics-server, argocd) dentro lo stesso cluster che sta per distruggere.

```bash
kubectl delete -f argocd/application.yaml   # il finalizer fa cascade delete delle risorse, incluso il volume EBS di mongodb

cd terraform-aws-eks
terraform destroy                            # disinstalla argocd/ingress-nginx/metrics-server, poi cluster/nodi/IAM
```

Verifica finale che non sia rimasto nulla a pagamento:
```bash
aws eks describe-cluster --name habit-tracker-cluster --region eu-west-1   # atteso: ResourceNotFoundException
aws elbv2 describe-load-balancers --region eu-west-1 --query 'LoadBalancers[]'
aws ec2 describe-volumes --region eu-west-1 --filters Name=status,Values=available --query 'Volumes[].VolumeId'
```

#### Note tecniche

**Nessuna StorageClass di default automatica**: la creazione automatica di una StorageClass gp3 da parte dell'add-on `aws-ebs-csi-driver` riguarda solo EKS Auto Mode. Su un node group gestito "standard" come questo, l'add-on installa solo il driver: la StorageClass va definita esplicitamente (vedi `kubernetes_storage_class.gp3_default`).

**Dimensionamento dei nodi**: un singolo `t3.small` non basta a ospitare contemporaneamente il driver EBS CSI, ingress-nginx, metrics-server e l'intera applicazione (mongodb, 2 repliche backend, frontend): si esaurisce sia la memoria disponibile sia il numero massimo di pod schedulabili per nodo. Il node group è configurato con `node_desired_size = 2` per questo motivo. Con l'aggiunta di ArgoCD il vincolo più stringente non è più la memoria, ma il numero massimo di pod per nodo: dettagli nella sezione "GitOps con ArgoCD" più sotto.

**Classic Load Balancer legacy di default**: senza annotazioni, il Service `LoadBalancer` di ingress-nginx farebbe provisionare un Classic Load Balancer (controller "in-tree", legacy, in sola manutenzione) invece di un Network Load Balancer. L'annotazione `service.beta.kubernetes.io/aws-load-balancer-type: nlb` nel `helm_release` risolve senza dover installare l'intero AWS Load Balancer Controller.

### GitOps con ArgoCD

Il deploy dell'app su EKS non avviene con `helm install`/`helm upgrade` manuale: è ArgoCD a tenere sincronizzato il cluster con lo stato dichiarato nel chart Helm (`charts/habit-tracker/`), letto direttamente da questo repository. È lo stesso Helm chart già usato su minikube e su EKS in modalità manuale, solo applicato in modo diverso.

#### Flusso

```
Terraform (terraform-aws-eks/)
   |
   v
Cluster EKS + node group + ingress-nginx + metrics-server + ArgoCD (helm_release)
   |
   | kubectl apply, una tantum
   v
ArgoCD Application (argocd/application.yaml)
   |
   | legge, in polling continuo
   v
Questo repository Git: charts/habit-tracker/ con values-eks.yaml
   |
   | applica, corregge il drift, rimuove le risorse non più presenti
   v
Cluster EKS: namespace habit-tracker (mongodb, backend, frontend)
```

1. Terraform crea il cluster EKS, il node group e installa via Helm (sempre da Terraform) `ingress-nginx`, `metrics-server` e ArgoCD stesso (`terraform-aws-eks/argocd.tf`).
2. Una tantum, si registra manualmente la Application di ArgoCD (`argocd/application.yaml`) con `kubectl apply`: è il solo passo manuale necessario per avviare il ciclo automatico.
3. Da quel momento ArgoCD confronta lo stato desiderato (`charts/habit-tracker` con `values-eks.yaml`) con lo stato reale del cluster, e:
   - applica automaticamente ogni modifica pushata su `main` (auto-sync)
   - annulla automaticamente ogni modifica manuale fuori standard, ad esempio un `kubectl scale` o `kubectl edit` (selfHeal)
   - rimuove le risorse non più presenti nel chart (prune)

#### Gestione dei secret

Le credenziali MongoDB non sono in Git. Il chart supporta nativamente `mongodb.auth.existingSecret`: se valorizzato, `templates/secret.yaml` non crea alcun Secret, e i Deployment leggono le credenziali da un Secret creato a mano nel cluster, fuori dal ciclo GitOps:

```bash
kubectl create namespace habit-tracker

kubectl create secret generic habit-tracker-mongodb-secret \
  -n habit-tracker \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD='<password>'
```

Namespace e secret vanno creati prima del primo sync di ArgoCD, altrimenti i pod restano in errore di configurazione finché il Secret non esiste.

#### Setup end-to-end

```bash
cd terraform-aws-eks
terraform apply

# password admin iniziale di ArgoCD
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

kubectl create namespace habit-tracker
kubectl create secret generic habit-tracker-mongodb-secret -n habit-tracker \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD='<password>'

kubectl apply -f argocd/application.yaml
kubectl get application habit-tracker -n argocd   # atteso: Synced / Healthy
```

Accesso alla UI (facoltativo):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080, utente admin, password recuperata sopra
```

A fine sessione, `terraform destroy` come descritto nella sezione precedente (il cluster EKS non è coperto dal free tier).

#### GitOps pull-based confrontato con il flusso precedente (push-based)

| | Flusso precedente (`helm install`/`upgrade` manuale, o `helm_release` in Terraform) | GitOps con ArgoCD |
|---|---|---|
| Chi avvia il deploy | Lo sviluppatore, da locale, con credenziali AWS/kubeconfig | ArgoCD, dall'interno del cluster |
| Credenziali verso il cluster | Devono uscire (kubeconfig, IAM) verso chi esegue il deploy | Restano dentro il cluster, solo ArgoCD vi accede |
| Stato desiderato | Implicito: quello che è appena stato eseguito | Esplicito e versionato: il chart in Git è la sola fonte di verità |
| Drift manuale (`kubectl edit`, `scale`, ecc.) | Resta finché qualcuno non rifà il deploy | Rilevato e annullato automaticamente (selfHeal) |
| Rollback | `helm rollback` a mano, serve accesso diretto al cluster | `git revert` più auto-sync, nessun accesso diretto necessario |
| Audit trail | Storia Helm locale/CI, non sempre centralizzata | Storia Git dei manifest, più storico dei sync di ArgoCD |
| Bootstrap iniziale | Non esiste, il primo deploy è già un push | Esiste comunque: la prima Application va applicata a mano una volta; il pull-based non elimina del tutto il push iniziale |

### Monitoring

Stack di osservabilità per l'applicazione, interamente locale e a costo zero: metriche applicative e di infrastruttura, dashboard versionata nel repository e alerting testato end to end. Le metriche dicono *cosa* sta succedendo; per capire *perché* si affianca il [logging centralizzato](#logging-centralizzato-stack-elk).

Principi seguiti:

- **Tutto è codice**: configurazione di Prometheus, regole, routing degli alert, datasource e dashboard di Grafana sono file nel repository. Nessun click manuale nella UI: `docker compose down -v && up` ricrea lo stesso identico ambiente.
- **Metodo RED** per il servizio (Rate, Errors, Duration) e metriche di saturazione per le risorse.
- **Alert testati**: le regole hanno unit test eseguiti in CI con `promtool`, più una procedura manuale di chaos testing.

#### Architettura

| Componente | Ruolo | Porta (solo localhost) |
|---|---|---|
| Prometheus | Raccoglie le metriche (pull), valuta recording e alerting rules | 9090 |
| Alertmanager | Raggruppa, deduplica, inibisce e instrada gli alert | 9093 |
| Grafana | Dashboard provisionata da file | 3000 |
| cAdvisor | Metriche dei container: CPU, memoria, rete | interna |
| mongodb-exporter | Metriche di MongoDB: connessioni, operazioni | interna |
| alert-receiver | Webhook locale che stampa le notifiche nei log | 5001 |

Lo stack aggiunge una rete `monitoring-net`, separata da quelle esistenti. Gli unici due container "ponte" sono il backend (per esporre `/metrics`) e l'exporter di MongoDB (che deve raggiungere il database). Prometheus e Grafana non sono su `backend-net` e quindi non hanno accesso diretto al database.

L'endpoint `/metrics` del backend non è esposto all'esterno: nginx inoltra solo `/api/`, quindi le metriche sono leggibili solo dalla rete interna. Tutte le porte del monitoring sono pubblicate su `127.0.0.1`, non sulla LAN.

#### Avvio rapido

```bash
cp .env.example .env        # imposta MONGO_ROOT_PASSWORD e GRAFANA_ADMIN_PASSWORD

docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps

./monitoring/scripts/load-test.sh 300   # 5 minuti di traffico per popolare i grafici
```

| URL | Cosa trovi |
|---|---|
| http://localhost | L'applicazione |
| http://localhost:3000 | Grafana (la dashboard è la home) |
| http://localhost:9090/targets | Stato degli scrape: tutti i target devono essere UP |
| http://localhost:9090/alerts | Regole di alerting e loro stato |
| http://localhost:9093 | Alertmanager: alert attivi, silenziati e inibiti |
| http://localhost:5001/alerts | Ultime notifiche ricevute dal webhook (JSON) |

Per evitare di ripetere i due `-f` a ogni comando:

```bash
export COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml
docker compose up -d
```

#### Metriche

**Applicative (backend, `prom-client`)**

| Metrica | Tipo | Label | Uso |
|---|---|---|---|
| `http_requests_total` | counter | `method`, `route`, `status_code` | Rate ed errori |
| `http_request_duration_seconds` | histogram | `method`, `route`, `status_code` | Latenza (percentili, heatmap) |
| `habit_tracker_habits_created_total` | counter | | Business: abitudini create |
| `habit_tracker_entries_recorded_total` | counter | | Business: entry registrate |
| `nodejs_*`, `process_*` | vari | | Heap, event loop lag, CPU (default metrics) |

Cardinalità sotto controllo: la label `route` contiene il template della route (`/api/habits/:id/entries`), mai il path reale con gli ID. Le richieste che non corrispondono a nessuna route finiscono tutte in `route="unmatched"`. Senza queste due regole, ogni ID e ogni URL casuale di uno scanner creerebbero una nuova serie temporale, facendo crescere senza limite la memoria di Prometheus. Il comportamento è coperto da test in `backend/tests/integration/metrics.test.js`.

Healthcheck (`/api/health`) e scrape (`/metrics`) sono esclusi dalle metriche di traffico, per non falsare le statistiche.

**Recording rules**

Definite in `monitoring/prometheus/rules/recording.yml` e usate sia dagli alert sia dalla dashboard: la soglia colorata in Grafana è esattamente la stessa espressione che fa scattare l'alert.

| Regola | Significato |
|---|---|
| `job:http_requests:rate5m` | Richieste al secondo (media 5 min) |
| `job:http_requests_errors:ratio_rate5m` | Quota di risposte 5xx |
| `job:http_request_duration_seconds:p95_5m` | Latenza al 95° percentile |
| `job:http_request_duration_seconds:p99_5m` | Latenza al 99° percentile |

#### Dashboard as code

La dashboard è in `monitoring/grafana/dashboards/habit-tracker.json` e viene caricata all'avvio tramite il provisioning (`monitoring/grafana/provisioning/`). Anche le datasource sono provisionate con `uid` fissi, così la dashboard non dipende da ID generati a runtime.

Sezioni della dashboard:

1. Panoramica: stato del backend, richieste/s, error rate, latenza p95, alert attivi.
2. Traffico HTTP (RED): richieste per route, risposte per status code, percentili di latenza, error rate per route, heatmap delle latenze.
3. Metriche di business: abitudini create ed entry registrate.
4. Runtime Node.js: heap V8, event loop lag, CPU del processo.
5. Container: CPU, memoria rispetto al `mem_limit`, traffico di rete.
6. MongoDB: stato, connessioni, operazioni al secondo.

Variabili: `$route` e `$container` per filtrare. Gli alert di Prometheus compaiono come annotazioni rosse sui grafici.

La dashboard non è modificabile dalla UI (`allowUiUpdates: false`). Per cambiarla: duplicala in Grafana, modificala, esporta il JSON (Share, Export), sostituisci il file nel repository e apri una PR. Grafana ricarica il file entro 30 secondi.

#### Alerting

| Alert | Condizione | For | Severità |
|---|---|---|---|
| `BackendDown` | Scrape del backend fallito | 1m | critical |
| `MongoDBDown` | L'exporter non raggiunge MongoDB | 1m | critical |
| `MonitoringTargetDown` | Un altro target non risponde | 2m | warning |
| `HighErrorRate` | 5xx sopra il 5% e traffico sopra 0.1 req/s | 2m | warning |
| `HighLatencyP95` | p95 sopra 500ms | 5m | warning |
| `NodeEventLoopLagHigh` | Event loop lag p99 sopra 200ms | 5m | warning |
| `ContainerMemoryNearLimit` | Working set sopra il 90% del `mem_limit` | 5m | warning |

Scelte di design:

- Il `for` evita notifiche su picchi di pochi secondi (flapping).
- `HighErrorRate` richiede un traffico minimo: con due richieste al minuto, una sola 5xx varrebbe il 50%.
- Inhibit rules in Alertmanager: se MongoDB è giù, le 5xx del backend sono un sintomo e non vengono notificate. Si riceve un solo alert sulla causa, non una raffica.
- Il receiver di default è un webhook locale, quindi nessun account o servizio esterno. In `alertmanager.yml` c'è un esempio commentato per Telegram.

**Unit test delle regole**

```bash
docker run --rm -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" -w /etc/prometheus \
  --entrypoint promtool prom/prometheus:v3.13.3 test rules tests/alerts.test.yml
```

I test in `monitoring/prometheus/tests/alerts.test.yml` simulano serie temporali sintetiche e verificano, ad esempio, che `BackendDown` resti in pending per il primo minuto e scatti dopo, che `HighErrorRate` non scatti con traffico trascurabile e che `ContainerMemoryNearLimit` ignori i container senza limite. Vengono eseguiti in CI a ogni modifica (`.github/workflows/monitoring.yml`), insieme alla validazione di compose, Prometheus, Alertmanager e dashboard.

**Test end to end (chaos testing)**

In un terminale segui le notifiche:

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs -f alert-receiver
```

Scenario 1, backend giù:

```bash
./monitoring/scripts/chaos.sh backend-down
```

1. Dopo circa 15-30 secondi, in http://localhost:9090/alerts `BackendDown` è in pending.
2. Dopo un minuto passa a firing e l'alert-receiver stampa `FIRING [critical] BackendDown`.
3. `./monitoring/scripts/chaos.sh restore`, dopo pochi minuti arriva `RESOLVED`.

Scenario 2, database giù (inibizione):

```bash
./monitoring/scripts/chaos.sh mongo-down
./monitoring/scripts/load-test.sh 300 5     # in un altro terminale: le richieste ora falliscono con 500
```

1. `MongoDBDown` scatta e viene notificato.
2. Con il traffico in errore anche `HighErrorRate` va in firing in Prometheus, ma in Alertmanager risulta inibito e non genera notifiche: una sola notifica sulla causa radice.
3. `./monitoring/scripts/chaos.sh restore`.

#### Troubleshooting

| Problema | Soluzione |
|---|---|
| Target `cadvisor` DOWN o pannelli container vuoti | Su alcuni host (es. Docker Desktop su macOS, WSL2) cAdvisor ha bisogno di più permessi: aggiungi `privileged: true` e `devices: ["/dev/kmsg"]` al servizio |
| Target `mongodb` UP ma `mongodb_up` uguale a 0 | Credenziali errate in `.env`. Se la password contiene caratteri speciali (`@`, `:`, `/`) va codificata in URL nel `MONGODB_URI` |
| Login Grafana non accetta la password del `.env` | La password admin si applica solo al primo avvio: `docker volume rm habit-tracker_grafana-data` e riavvia |
| Pannelli "No data" subito dopo l'avvio | Le `rate` su finestre di 5 minuti hanno bisogno di qualche scrape: lancia `load-test.sh` e attendi 1-2 minuti |
| Modifiche a regole o `prometheus.yml` | `curl -X POST http://localhost:9090/-/reload` (senza riavviare il container) |

#### Possibili sviluppi

- Utente MongoDB dedicato all'exporter con il solo ruolo `clusterMonitor`, invece delle credenziali root (principio del minimo privilegio).
- Receiver reale (Telegram, Discord o email) con segreti montati da file.
- SLO espliciti (es. 99% di richieste sotto i 300ms) con alert di tipo burn rate.
- Log e metriche sulla stessa schermata, aggiungendo Elasticsearch come datasource di Grafana.
- Porting dello stack su Kubernetes con `kube-prometheus-stack` e `ServiceMonitor`.

### Logging centralizzato (Stack ELK)

Stack di logging per l'applicazione, interamente locale e a costo zero: i log di backend e nginx vengono raccolti, normalizzati e resi consultabili in Kibana, con una dashboard versionata nel repository. Completa il [Monitoring](#monitoring): le metriche dicono *cosa* sta succedendo, i log aiutano a capire *perché*.

Principi seguiti:

- **Tutto è codice**: configurazione di Filebeat, pipeline di Logstash e dashboard di Kibana sono file nel repository, e la dashboard si ricrea con un solo comando di import.
- **Log strutturati alla fonte**: il backend scrive JSON, così il parsing è banale e robusto. Per nginx, che scrive testo, si usa un pattern grok calibrato sul suo formato.
- **Schema comune**: i due servizi finiscono negli indici con gli stessi nomi di campo per lo status HTTP e il metodo, quindi un grafico può coprire entrambi.
- **L'applicazione non dipende dallo stack**: se ELK è spento o in errore, Habit Tracker funziona normalmente.

#### Architettura

```
backend (Winston, JSON) ──► volume backend-logs ─┐
                                                 ├─► Filebeat ──► Logstash ──► Elasticsearch ──► Kibana
frontend (access log nginx) ► volume nginx-logs ─┘   (raccolta)   (parsing)    (indicizzazione)   (dashboard)
```

| Servizio | Ruolo | Porta (solo localhost) | mem_limit / cpus |
|---|---|---|---|
| `filebeat` | Legge i file di log dai volumi condivisi (in sola lettura) e li inoltra a Logstash | nessuna | 256m / 0.3 |
| `logstash` | Filtra, normalizza e arricchisce gli eventi | nessuna | 768m / 0.7 (heap JVM 256m) |
| `elasticsearch` | Indicizza gli eventi (un indice al giorno per servizio) | `127.0.0.1:9200` | 1g / 1.0 (heap JVM 512m) |
| `kibana` | Esplorazione dei log e dashboard | `127.0.0.1:5601` | 1g / 0.5 |

I quattro componenti devono avere la stessa versione, controllata dalla variabile `ELASTIC_VERSION` (default `9.4.6`). Lo stack occupa circa 2-3 GB di RAM.

Perché file su volume condiviso invece dell'autodiscovery di Filebeat sui log dei container Docker: quest'ultima richiede di montare il socket Docker e i path interni di Docker, che differiscono tra Linux nativo e Docker Desktop. Con i volumi il progetto si comporta allo stesso modo su qualunque sistema.

Elasticsearch gira in modalità `single-node` con la sicurezza disattivata: configurazione accettabile solo in locale, per questo tutte le porte sono legate a `127.0.0.1`.

#### File Compose, volumi e ordine di avvio

Lo stack vive in `docker-compose.logging.yml`, da sovrapporre a `docker-compose.yml` (vedi [Stack opzionali](#stack-opzionali-add-on)). Il file:

- aggiunge i quattro servizi e la rete `logging-net`, alla quale appartengono solo loro
- definisce i volumi `backend-logs` e `nginx-logs` e li monta sia su `backend` e `frontend` (in scrittura, con un override dei due servizi) sia su Filebeat (in sola lettura): backend e frontend condividono i log con Filebeat esclusivamente tramite volumi
- definisce `es-data` (indici Elasticsearch, dashboard e data view di Kibana) e `filebeat-data` (registry con la posizione raggiunta in ogni file)

Senza questo file l'applicazione funziona in modo identico: i log restano nel filesystem del container e su stdout.

L'ordine di avvio è garantito da `depends_on` con `condition: service_healthy`:
```
elasticsearch (healthy) → kibana
elasticsearch (healthy) → logstash → filebeat
```

| Servizio | Healthcheck |
|---|---|
| `elasticsearch` | `curl` su `/_cluster/health?wait_for_status=yellow` |
| `kibana` | `curl` su `/api/status`, atteso `"level":"available"` |

`logstash` e `filebeat` non hanno un healthcheck: Filebeat ritenta da solo la connessione a Logstash finché non è pronto. L'applicazione non dipende dallo stack: se Elasticsearch o Kibana non partono, Habit Tracker continua a funzionare.

#### Log prodotti dall'applicazione

**Backend** (`backend/src/logger.js`, Winston): una riga JSON per evento, scritta sia su file (`/app/backend/logs/backend.log`, volume `backend-logs`) sia su stdout (JSON con `NODE_ENV=production`, formato colorato e leggibile in sviluppo). Un middleware in `app.js` registra ogni richiesta come `http_request`, con:

- `method` e `path` reali, e `route` con il template della route (`/api/habits/:id/entries`), la stessa normalizzazione usata per le metriche Prometheus, così i grafici non si frammentano per ogni ID
- `status` e `duration_ms`
- livello in base allo status: `info` sotto 400, `warn` per i 4xx, `error` per i 5xx

Gli errori non gestiti sono registrati come `unhandled_error` con lo stack. `/api/health` e `/metrics` non producono righe di log perché sono registrati prima del middleware.

```json
{"duration_ms":14,"level":"info","message":"http_request","method":"GET","path":"/api/habits","route":"/api/habits","service":"habit-tracker-backend","status":200,"timestamp":"2026-09-28T08:23:05.308Z"}
```

**Frontend** (nginx): l'access log è scritto in un formato "combined" esplicito (`log_format combined_log` in `frontend/nginx.conf`) su `/var/log/app-logs/nginx/access.log`, volume `nginx-logs`. Il log di default su stdout resta attivo, quindi `docker compose logs frontend` funziona come prima.

```
172.19.0.1 - - [28/Sep/2026:08:23:05 +0000] "GET /api/habits HTTP/1.1" 200 385 "-" "curl/8.14.1"
```

#### Pipeline

Filebeat (`elk/filebeat/filebeat.yml`) legge i due file con input di tipo `filestream`, aggiunge il campo `fields.service` (`backend` o `frontend`) e invia tutto a Logstash sulla porta 5044. Il "registry" con la posizione raggiunta in ogni file è nel volume `filebeat-data`, quindi un riavvio non rispedisce i log già inviati.

Logstash (`elk/logstash/pipeline/logstash.conf`) applica filtri diversi in base al servizio:

| Servizio | Formato in ingresso | Filtri | Campi risultanti |
|---|---|---|---|
| `backend` | JSON | `json`, `date`, `mutate rename` | `log.level`, `http.request.method`, `url.path`, `http.response.status_code`, `route`, `duration_ms` |
| `frontend` | testo (combined) | `drop` delle righe dell'healthcheck, `grok` personalizzato, `date` | `source.address`, `http.request.method`, `url.original`, `http.response.status_code`, `http.response.body.bytes`, `user_agent.original` |

Dettagli utili:

- `@timestamp` è l'orario dell'evento originale, non quello di ricezione.
- La riga originale resta disponibile in `event.original`.
- Le richieste dell'healthcheck di Docker (user-agent `Wget`, ogni 30 secondi) sono scartate: falserebbero i grafici sul traffico.
- I campi temporanei usati durante il parsing stanno sotto `[@metadata]` e non vengono indicizzati.
- Il campo `http.response.status_code` ha lo stesso nome e lo stesso tipo numerico in entrambi gli indici.
- L'`error.log` di nginx non è raccolto: ha un formato diverso dall'access log e richiederebbe un pattern dedicato.

Indici creati: `habit-tracker-backend-YYYY.MM.dd` e `habit-tracker-frontend-YYYY.MM.dd`.

#### Avvio

Requisiti: circa 4 GB di RAM libera per lo stack ELK. Su Linux, Elasticsearch richiede inoltre `vm.max_map_count` di almeno 262144:

```bash
sysctl vm.max_map_count                          # se è inferiore a 262144:
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
```

Avvio e verifica. I comandi di questa sezione assumono `COMPOSE_FILE` esportato, perché i servizi dello stack esistono solo nel file di logging:

```bash
export COMPOSE_FILE=docker-compose.yml:docker-compose.logging.yml
docker compose up -d --build
docker compose ps        # Elasticsearch e Kibana impiegano 1-2 minuti a diventare healthy
```

Genera un po' di traffico, con anche qualche errore 4xx, e controlla che gli indici si popolino:

```bash
./monitoring/scripts/load-test.sh 60
curl -s -o /dev/null localhost/api/habits/id-non-valido/entries     # 400
curl -s -o /dev/null localhost/api/non-esiste                        # 404

curl -s "localhost:9200/_cat/indices?v"
```

Devi vedere i due indici `habit-tracker-backend-*` e `habit-tracker-frontend-*` con `docs.count` maggiore di zero. Lo stato `yellow` degli indici è normale: chiedono una replica che un cluster a un solo nodo non può assegnare.

| URL | Cosa trovi |
|---|---|
| http://localhost:5601 | Kibana |
| http://localhost:9200 | API di Elasticsearch |

**Importare la dashboard.** Il file `elk/kibana/habit-tracker-dashboard.ndjson` contiene la dashboard e il data view. Va importato una volta, con Kibana `healthy`:

```bash
curl -s -X POST "localhost:5601/api/saved_objects/_import?overwrite=true" \
  -H 'kbn-xsrf: true' --form file=@elk/kibana/habit-tracker-dashboard.ndjson
```

Nella risposta cerca `"success":true`. Poi apri **Dashboards, Habit Tracker - Logging** e imposta l'intervallo su "Last 1 hour".

#### Dashboard

![Dashboard Kibana](screenshots/kibana-dashboard.png)

| Pannello | Filtro (KQL) | Cosa mostra |
|---|---|---|
| Richieste nginx per status code | `fields.service : "frontend"` | Conteggio nel tempo, suddiviso per `http.response.status_code` |
| Log backend per livello | `fields.service : "backend"` | Ripartizione per `log.level.keyword` (`info`, `warn`, `error`) |
| Latenza media per rotta (ms) | `fields.service : "backend"` | Media di `duration_ms` per `route.keyword` |
| Richieste per rotta | `fields.service : "backend"` | Conteggio per `route.keyword` |

Le richieste a `/api/...` vengono registrate due volte, una da nginx e una dal backend: per questo ogni pannello filtra per servizio. Un conteggio sull'intero data view conterebbe ogni richiesta due volte.

Per raggruppare per campi testuali in Kibana si usa la variante `.keyword` (`log.level.keyword`, `route.keyword`, `url.path.keyword`).

**Modificare la dashboard.** Cambiala in Kibana, salva, poi riesporta il file e committalo:

```bash
curl -s -X POST "localhost:5601/api/saved_objects/_export" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"type":["dashboard"],"includeReferencesDeep":true}' \
  -o elk/kibana/habit-tracker-dashboard.ndjson
```

L'export contiene l'oggetto dashboard, che incorpora i quattro pannelli, e il data view.

#### Verifiche e comandi utili

```bash
curl -s "localhost:9200/_cat/indices?v"                                          # indici e numero di documenti
curl -s "localhost:9200/habit-tracker-backend-*/_search?q=log.level:warn&size=1&pretty"   # un log di livello warn
curl -s "localhost:9200/habit-tracker-*/_count?q=tags:*failure&pretty"           # 0 = nessun parsing fallito

docker compose logs --tail=30 filebeat           # lettura dei file e connessione a Logstash
docker compose logs --tail=30 logstash           # avvio della pipeline ed errori di filtro
docker compose restart logstash                  # dopo ogni modifica a logstash.conf (non si ricarica da solo)
```

Per eliminare indici vecchi vanno indicati i nomi completi, perché Elasticsearch rifiuta per default le cancellazioni con wildcard:
```bash
curl -X DELETE "localhost:9200/habit-tracker-backend-2026.09.28,habit-tracker-frontend-2026.09.28"
```

#### Troubleshooting

| Problema | Soluzione |
|---|---|
| Nessun indice `habit-tracker-*` subito dopo l'avvio | Logstash impiega circa un minuto ad avviare la pipeline e Filebeat ritenta da solo. Attendi, genera traffico e ricontrolla `_cat/indices` |
| Indici ancora assenti dopo qualche minuto | Controlla nell'ordine `docker compose logs logstash` e `docker compose logs filebeat`, e verifica che Filebeat veda i file con `docker compose exec filebeat ls -l /logs/backend /logs/nginx` |
| Elasticsearch non diventa `healthy` o si riavvia | Controlla `vm.max_map_count` e la RAM disponibile. In ultima istanza alza `ES_JAVA_OPTS` e `mem_limit` nel compose |
| Filebeat esce con un errore sui permessi del `filebeat.yml` | Filebeat pretende che il file appartenga a root: il servizio è già avviato con `--strict.perms=false`, verifica che il comando non sia stato rimosso |
| Documenti con tag `_grokparsefailure` o `_jsonparsefailure` | Una riga non rispetta il formato atteso. Guarda il campo `message` del documento e confrontalo con il pattern in `logstash.conf` |
| Un campo non compare tra le opzioni di Kibana (per esempio `route.keyword`) | Non ci sono ancora documenti con quel campo nell'intervallo di tempo scelto. Genera traffico, allarga l'intervallo e usa "refresh fields list" nelle impostazioni del data view |
| La dashboard importata è vuota | I pannelli mostrano solo i log dell'intervallo selezionato. Genera traffico e scegli "Last 1 hour" |
| Errore `no such service` (per esempio `filebeat`) | Il file di logging non è incluso nel comando: esporta `COMPOSE_FILE` come nella sezione Avvio, oppure aggiungi `-f docker-compose.logging.yml` |
| Errore al pull delle immagini ELK | Verifica che la versione in `ELASTIC_VERSION` esista come tag su `docker.elastic.co` |

#### Note e limiti

- Sicurezza di Elasticsearch disattivata e porte legate a `127.0.0.1`: configurazione adatta solo a un ambiente locale.
- I file di log non hanno rotazione e gli indici non hanno una politica di retention: in un ambiente reale si introdurrebbero la rotazione di Winston e una policy ILM.
- Elasticsearch, Kibana, Logstash e Filebeat devono avere la stessa versione, per questo è controllata da una sola variabile (`ELASTIC_VERSION`, default `9.4.6`).
- La pipeline copre il deploy Docker Compose. Nei deploy Kubernetes, EKS ed EC2 i log JSON del backend escono comunque su stdout (`kubectl logs`, `docker logs`), ma lo stack ELK non è portato su quegli ambienti.
- Il volume `es-data` contiene anche dashboard e data view di Kibana: per rigenerarli basta rieseguire l'import.

#### Possibili sviluppi

- Rotazione dei log del backend (`maxsize` e `maxFiles` nel transport `File` di Winston) e policy ILM per la retention degli indici.
- Raccolta dell'`error.log` di nginx con un input e un pattern dedicati.
- Autenticazione e TLS su Elasticsearch e Kibana.
- Correlazione tra metriche e log in Grafana, con Elasticsearch come datasource.
- Porting su Kubernetes con Filebeat come DaemonSet.

---

## English

### Description

A minimal app for logging daily habits (e.g. "Drink 2L of water") and marking them done day by day. The React frontend talks to a Node/Express REST backend, which persists data to MongoDB.

The focus of this project is containerization and orchestration: multi-stage Dockerfiles, network/secrets/persistence management across the three services, orchestrated with Docker Compose and, alternatively, with Kubernetes and a Helm chart that parametrizes the deployment and adds autoscaling, with a CI/CD pipeline that automates testing and image release. The same Docker stack can also be provisioned declaratively with Terraform, both locally (`terraform-docker/`) and on AWS with an end-to-end production infrastructure (EC2, Secrets Manager, IAM) under `terraform-aws/`, with a Docker registry and CI permissions shared across the AWS deployments under `terraform-aws-shared/`. The same Helm chart used on minikube can finally be deployed to a real managed Kubernetes cluster (Amazon EKS), also provisioned with Terraform, under `terraform-aws-eks/`.

The application is observable through two complementary approaches: metrics (Prometheus, Alertmanager, Grafana) tell you *what* is happening, while centralized logs with the ELK stack (Filebeat, Logstash, Elasticsearch, Kibana) help you understand *why*. The backend produces structured JSON logs, nginx writes its access log to a file, and a dedicated pipeline collects them, normalizes them and makes them searchable in a Kibana dashboard versioned in the repository.

Development work is tracked on a Jira Kanban board linked to this repository via the "GitHub for Atlassian" app: commits can reference Jira issues (e.g. HTKB-1 #done) and automatically update their status through Smart Commits.

### Tech stack

- **Frontend**: React 19, Vite, served in production by nginx
- **Backend**: Node.js 20, Express, Mongoose
- **Database**: MongoDB 7
- **Testing**: Vitest (frontend and backend), Supertest, mongodb-memory-server, React Testing Library
- **Containerization**: Docker, Docker Compose
- **Orchestration**: Kubernetes (raw manifests in `k8s/`) and Helm (chart in `charts/habit-tracker/`), both validated on a local minikube cluster
- **Infrastructure as Code**: Terraform, `kreuzwerker/docker` provider for the local stack (`terraform-docker/`), `hashicorp/aws` provider for the production deployment on EC2 (`terraform-aws/`), for an Amazon EKS cluster (`terraform-aws-eks/`), and for resources shared between the two (`terraform-aws-shared/`)
- **Monitoring**: Prometheus, Alertmanager, Grafana (dashboard as code), cAdvisor, mongodb-exporter; application metrics via `prom-client`
- **Logging**: structured JSON logs with Winston, ELK stack (Filebeat, Logstash, Elasticsearch, Kibana) for collection, parsing and visualization

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

The flow of backend and nginx logs into the ELK stack is described in the [Centralized logging](#centralized-logging-elk-stack) section.

### Repository structure

```
habit-tracker/
├── README.md                    # this file
├── docker-compose.yml           # local orchestration of the 3 services (mongodb, backend, frontend)
├── docker-compose.aws.yml       # orchestration for EC2 deployment (images from ECR)
├── docker-compose.monitoring.yml # monitoring stack (add-on): Prometheus, Alertmanager, Grafana, exporters
├── docker-compose.logging.yml   # centralized logging stack (add-on): Filebeat, Logstash, Elasticsearch, Kibana
├── elk/                         # logging stack configuration (details in the Logging section below)
│   ├── filebeat/
│   │   └── filebeat.yml           # inputs on the log volumes, output to Logstash
│   ├── logstash/
│   │   └── pipeline/
│   │       └── logstash.conf      # filters: json (backend), grok + healthcheck drop (nginx), output to Elasticsearch
│   └── kibana/
│       └── habit-tracker-dashboard.ndjson  # exported dashboard, importable via API
├── screenshots/
│   └── kibana-dashboard.png     # Kibana dashboard image used in this README
├── monitoring/                  # monitoring configuration and tooling (details in the Monitoring section below)
│   ├── prometheus/               # prometheus.yml, recording rules, alerting rules, promtool unit tests
│   ├── alertmanager/              # routing, receiver, inhibit rules
│   ├── alert-receiver/            # local webhook that logs notifications
│   ├── grafana/                   # datasources and dashboard provisioned from files
│   └── scripts/                   # load-test.sh (traffic) and chaos.sh (failure simulation)
├── .env.example                 # template for variables read by Compose (Mongo credentials, ELK stack version)
├── .gitignore
├── package.json                 # aggregator script: runs backend + frontend tests
│
├── backend/                     # details in backend/README.md
│   ├── Dockerfile                # multi-stage: build → test → production
│   ├── .dockerignore
│   ├── .env                      # only for local execution outside Docker
│   ├── src/
│   │   ├── app.js                # Express app (no side effects, importable in tests): metrics, request logging, routes
│   │   ├── server.js             # real entry point: connectDB() + app.listen()
│   │   ├── db.js                 # MongoDB connection
│   │   ├── logger.js             # Winston logger: JSON to file (backend-logs volume) and to stdout
│   │   ├── metrics.js            # Prometheus metrics (prom-client) and middleware
│   │   ├── models/
│   │   │   ├── Habit.js
│   │   │   └── Entry.js
│   │   └── routes/
│   │       └── habitsRoute.js
│   └── tests/
│       ├── setup.js              # in-memory MongoDB shared across tests
│       ├── unit/                 # isolated model tests
│       └── integration/          # HTTP route and metrics tests (Supertest)
│
├── frontend/                    # details in frontend/README.md
│   ├── Dockerfile                 # multi-stage: build (Node) → test → production (nginx)
│   ├── .dockerignore
│   ├── .env                       # optional local override (VITE_API_BASE_URL)
│   ├── .gitignore
│   ├── .oxlintrc.json              # linter configuration (oxlint)
│   ├── nginx.conf                  # reverse proxy /api/ → backend:5000 + access log to file (combined format)
│   ├── src/
│   │   ├── App.jsx
│   │   ├── App.css
│   │   └── api.js                  # fetch wrapper, relative base URL by default
│   └── tests/
│       ├── setup.js                # import '@testing-library/jest-dom'
│       └── unit/
│           └── App.test.jsx
│
├── terraform-docker/               # details in the "Terraform - Local Docker" section below
│   ├── main.tf                     # provider, networks, volume, images, containers
│   ├── variables.tf                # variables with defaults and validation
│   ├── outputs.tf                  # ids/names of created resources + access URL
│   ├── terraform.tfvars.example    # value template (no real secrets)
│   ├── .terraform.lock.hcl         # Terraform lock file
│   └── .gitignore                  # excludes state, .terraform/, real *.tfvars
│
├── terraform-aws-shared/            # details in the "Terraform - Shared" section below
│   ├── providers.tf
│   ├── variables.tf
│   ├── ecr.tf                       # ECR repositories + lifecycle policy
│   ├── github-oidc.tf               # GitHub OIDC provider + role for the CD's push
│   └── outputs.tf
│
├── terraform-aws/                  # details in the "Terraform - AWS" section below
│   ├── providers.tf
│   ├── variables.tf
│   ├── network.tf                  # data source for the default VPC/subnets
│   ├── security.tf                 # security group
│   ├── iam.tf                      # role + instance profile
│   ├── secrets.tf                  # Mongo secret + random_password
│   ├── s3.tf                       # MongoDB backup bucket + lifecycle
│   ├── ec2.tf                      # key pair + instance + user_data
│   ├── outputs.tf
│   ├── terraform.tfvars            # not committed: SSH IP, public key, image tags
│   └── templates/
│       └── user_data.sh.tpl        # bootstrap script run on first EC2 boot
│
├── terraform-aws-eks/               # details in the "Kubernetes on AWS (EKS)" section below
│   ├── providers.tf
│   ├── variables.tf
│   ├── network.tf                   # subnet tags required by EKS
│   ├── iam.tf                       # roles for the cluster and the node group
│   ├── eks.tf                       # cluster, access entry, node group, IRSA for the EBS CSI driver
│   ├── kubernetes.tf                # kubernetes/helm providers, ingress-nginx, metrics-server, StorageClass
│   ├── argocd.tf                    # installs ArgoCD via Helm, managed by Terraform
│   ├── outputs.tf
│   ├── terraform.tfvars             # not committed: node_desired_size, etc.
│   └── terraform.tfvars.example
│
├── argocd/                      # details in the "GitOps with ArgoCD" section below
│   └── application.yaml         # Application that syncs charts/habit-tracker from this repository
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
    ├── values-eks.yaml                # overrides for the EKS deployment (images from ECR, external Mongo secret for the GitOps flow)
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

Monitoring and centralized logging are not in the main file: they are add-ons in separate Compose files, layered on top of `docker-compose.yml` when needed (see [Optional stacks](#optional-stacks-add-ons)).

#### Images and multi-stage builds

Both `backend/Dockerfile` and `frontend/Dockerfile` follow a **four-stage** structure, and the build context is the **repository root** (no longer the individual subfolders): required because the project uses npm workspaces with a single shared `package-lock.json`.

| Stage | Purpose | Ends up in the final image? |
|---|---|---|
| `deps` | Installs the entire workspace's dependencies (root + backend + frontend) | No |
| `build` | Inherits from `deps`, adds the service's source code | No |
| `test` | Inherits from `build`, runs the test suite (`npm run test`) | No |
| `production` | Final image, only what's needed at runtime | Yes |

The `test` stage **is** referenced by `production` via `COPY --from=test <a harmless file>`: an explicit gate that forces Docker to build (and run) `test` as a prerequisite. If `npm run test` fails, the whole image build stops before producing `production`. To run just the test stage in isolation:
```bash
docker build --target test -t habit-tracker-backend-test -f backend/Dockerfile .
```

**Backend**: the `deps` stage uses `node:20.19`. With npm workspaces, `npm ci` always installs the entire monorepo tree, including the frontend's devDependencies (rolldown, which requires glibc, see below). The `production` stage uses `node:20.19-alpine`: `npm ci --omit=dev` excludes all devDependencies in the workspace, rolldown included. The `production` stage also creates `/app/backend/logs` owned by `node`: the process runs as non-root and must be able to write the log file, which, when the logging stack is active, is mounted on a volume shared with Filebeat.

**Frontend**: the `deps`, `build` and `test` stages use `node:20.19`. The `production` stage is `nginx:alpine`: no Node in the final image, only the compiled static files (`dist/`). The `production` stage also creates `/var/log/app-logs/nginx`, where nginx writes its access log (mounted on a volume shared with Filebeat when the logging stack is active). No `chown` is needed: nginx's master process runs as root and opens the file itself.

In both Dockerfiles, the `package.json` files (root + both workspaces) are copied and installed in the `deps` stage before the application source code: the dependency layer stays cached when only the code changes.

#### Networking

Two separate Compose networks:
```yaml
networks:
  frontend-net:   # frontend ↔ backend
  backend-net:    # backend ↔ mongodb
```
The `backend` service is the only one present on both networks. `frontend` and `mongodb` have no direct visibility of each other. The optional stacks add their own networks (`monitoring-net`, `logging-net`) without changing these.

#### Persistence

```yaml
volumes:
  mongo-data:
```
A named volume mounted at `/data/db` inside the `mongodb` container. `docker compose down` preserves data; only `docker compose down -v` deletes it. The logging stack adds its own volumes (logs, Elasticsearch indices), described in its section: `down -v` deletes those too.

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

Other variables:

- `IMAGE_TAG` (optional, default `v0.2.0`) selects the tag of the `backend` and `frontend` images, both when reading (`up`, `pull`) and when writing (`build`, `push`).
- `NODE_ENV=production` is set on the `backend` service in the compose file: stdout logs are JSON, consistent with those written to file.
- `LOG_DIR` and `LOG_LEVEL` (optional) control the backend logger's folder and minimum level. Defaults: `backend/logs` and `info`.
- `ELASTIC_VERSION` (optional, default `9.4.6`) pins the version of the four ELK stack components: see the centralized logging section.

#### Healthchecks and startup order

`depends_on` with `condition: service_healthy` guarantees the order:
```
mongodb (healthy) → backend (healthy) → frontend
```

| Service | Healthcheck |
|---|---|
| `mongodb` | `mongosh -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval "db.adminCommand('ping')"` |
| `backend` | `wget -qO- http://localhost:5000/api/health` |
| `frontend` | `wget -qO- http://127.0.0.1:80` |

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

#### Optional stacks (add-ons)

Monitoring and centralized logging live in separate Compose files, layered on top of the main one. The application depends on neither and stays lightweight when they are not needed.

| File | Contents | Section |
|---|---|---|
| `docker-compose.yml` | Application: `mongodb`, `backend`, `frontend` | this one |
| `docker-compose.monitoring.yml` | Prometheus, Alertmanager, Grafana, exporters | [Monitoring](#monitoring-1) |
| `docker-compose.logging.yml` | Filebeat, Logstash, Elasticsearch, Kibana | [Centralized logging](#centralized-logging-elk-stack) |

```bash
# application + logging
docker compose -f docker-compose.yml -f docker-compose.logging.yml up -d

# application + monitoring + logging
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml -f docker-compose.logging.yml up -d

# to avoid repeating the -f flags (the separator is ":" on Linux and macOS)
export COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml:docker-compose.logging.yml
docker compose up -d
```

Services defined only in an add-on (for example `filebeat`) are visible to `logs`, `ps` and `restart` only if that file is included: to stop and inspect, use the same files you started with. If you start with a subset of the files, Compose flags the containers of the other running stacks as *orphans*: it is a warning, and `--remove-orphans` stops and removes them.

#### Registry

The `backend` and `frontend` images are published to GitHub Container Registry, referenced in `docker-compose.yml` next to `build:`. The tag is parametrized with `IMAGE_TAG`, defaulting to `v0.2.0`:

```yaml
backend:
  build:
    context: .
    dockerfile: backend/Dockerfile
  image: ghcr.io/frapanca/habit-tracker-backend:${IMAGE_TAG:-v0.2.0}

frontend:
  build:
    context: .
    dockerfile: frontend/Dockerfile
  image: ghcr.io/frapanca/habit-tracker-frontend:${IMAGE_TAG:-v0.2.0}
```

`mongodb` is excluded: it uses the official `mongo:7` image, never pushed. The same goes for the optional stacks' components, which use official images.

The tag identifies the image version: `docker compose build` builds it under that name and `docker compose push` publishes it under the same one. To work on a version other than the default:
```bash
IMAGE_TAG=<tag> docker compose build backend frontend
IMAGE_TAG=<tag> docker compose push backend frontend
```
(or set `IMAGE_TAG=<tag>` in `.env`). A manual push requires a prior login:
```bash
docker login ghcr.io -u <username>
```
(with a Personal Access Token scoped to `write:packages`, never a plaintext password)

Releases published by the CD (see [CI/CD](#cicd-1)) use the release's Git tag and the commit's short SHA: they are immutable references, unlike a tag such as `latest`, which would be overwritten on every push.

#### Technical notes

**Vite/rolldown and Alpine**: the frontend build fails on `node:20-alpine` with an error about `@rolldown/binding-linux-x64-musl` (a native binary compiled for glibc, incompatible with `musl`). The frontend's `deps`/`build`/`test` stages use `node:20.19`; the `production` stage stays `nginx:alpine`. With npm workspaces this constraint also propagates to the **backend**'s `deps` stage, which installs the frontend's devDependencies regardless: see "Images and multi-stage builds" above.

**`VITE_*` variables**: replaced at build time (`npm run build`), not read in the browser at runtime. The frontend's `.env` is excluded via `.dockerignore` and isn't present during the Docker build. `api.js` uses `/api` as the default value (`import.meta.env.VITE_API_BASE_URL || '/api'`).

**Dependencies and lockfile**: the backend's dependencies (including `winston`) are declared in `backend/package.json`, but the lockfile is a single one at the root. After any dependency change it must be regenerated with `npm install` from the root (for example `npm install winston -w backend`) and committed together with `package.json`: `npm ci` in the Dockerfiles fails if the two files are out of sync.

**Log files and permissions**: the backend runs as the `node` user, so the log folder must be created and assigned to `node` in the Dockerfile before the `USER` instruction. When Docker mounts a named volume for the first time on a folder that already exists in the image, it inherits its contents and permissions: that is why the `backend-logs` volume is writable by the backend. nginx, which opens the file as root, doesn't have this constraint.

### Quick setup

```bash
git clone <repo-url>
cd habit-tracker
cp .env.example .env   # and fill in MONGO_ROOT_PASSWORD

docker compose up --build
docker compose ps      # verify all services report "healthy"
```

App available at `http://localhost`. To add monitoring and centralized logging see [Optional stacks](#optional-stacks-add-ons).

### Testing

Automated test suite for both backend and frontend, runnable with a single command from the root:
```bash
npm test
```
(equivalent to `npm run test:backend && npm run test:frontend`, stops at the first failure). Details on framework, mocking strategy and coverage in the [`backend/`](backend/README.md#testing) and [`frontend/`](frontend/README.md#testing) READMEs.

### CI/CD

Two separate GitHub Actions workflows, with different triggers and different purposes:

| Workflow | File | Trigger | Purpose |
|---|---|---|---|
| CI | `.github/workflows/ci.yml` | push/PR to `main` | Continuous verification on every change: lint, test, security audit, build |
| CD | `.github/workflows/cd.yml` | push of a `v*.*.*` tag | Build and publish Docker images to GHCR, only for releases |

A generic push to `main` only triggers CI; a release tag only triggers CD. The two Git events (branch update vs tag creation) never overlap on the same trigger.

#### CI

5 jobs, sequenced/parallelized via dependencies (`needs`):

```
lint → test (matrix: Node 20, 22) ─┐
     → security (npm audit + Trivy) ┼→ build → ci-success
```

- **lint**: runs the linter across the whole project.
- **test**: matrix across two Node versions; the `mongodb-memory-server` binary is cached between runs (`actions/cache`) to avoid repeated downloads; coverage is uploaded as an artifact only for Node 20.
- **security**: `npm audit --audit-level=high` plus a filesystem scan with Trivy (CVEs and secret leaks), both failing the job (`exit-code: 1`) on high/critical findings.
- **build**: an actual build of the application, artifact retained for 5 days.
- **ci-success**: a "sentinel" job that depends on all the others, useful as a single required check for a branch protection rule.

#### CD

```yaml
strategy:
  matrix:
    service: ['backend', 'frontend']
```

A single job, parameterized with a matrix over `service`: GitHub Actions runs it twice in parallel (once for `backend`, once for `frontend`), avoiding duplicated steps per service.

On every run:
1. login to `ghcr.io` with `GITHUB_TOKEN` (no secret/PAT to manage manually: the `packages: write` permission declared in the workflow is enough, provided the repository's "Workflow permissions" is set to *Read and write* under Settings → Actions → General)
2. login to Amazon ECR by assuming an IAM role via OIDC (no static AWS keys stored on GitHub, see "Terraform - Shared" below)
3. build the image with **two tags**: the release's Git tag (`${{ github.ref_name }}`, e.g. `v1.0.0`) and the commit's short SHA, for traceability, applied to both the GHCR and ECR references
4. push both tags to both registries with `docker push --all-tags`

The image owner is lowercased (`${GITHUB_REPOSITORY_OWNER,,}`) since Docker references don't allow uppercase letters.

**Releasing a new version:**
```bash
git tag v1.0.0
git push origin v1.0.0
```
Images published to GHCR are visible at `https://github.com/<owner>?tab=packages`; the ones on ECR with `aws ecr describe-images --repository-name habit-tracker-backend`.

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
docker build -t habit-tracker-backend:dev  -f backend/Dockerfile .
docker build -t habit-tracker-frontend:dev -f frontend/Dockerfile .

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

### Terraform - Local Docker

Alternative provisioning of the same Docker stack (mongodb + backend + frontend) via Infrastructure as Code, parallel to Docker Compose: same images (backend/frontend from GHCR, mongodb from Docker Hub), same network topology, but declared with Terraform resources instead of a `docker-compose.yml` file. Files live in `terraform-docker/`. The ELK logging stack is not part of this provisioning: it remains specific to Docker Compose.

#### Provider and versions

| Component | Version |
|---|---|
| Terraform | `>= 1.5.0` |
| Provider `kreuzwerker/docker` | `~> 3.0` |

The provider connects to the local Docker daemon via the default socket (`/var/run/docker.sock`).

#### Managed resources

| Terraform resource | Name | Purpose |
|---|---|---|
| `docker_network` | `backend_network`, `frontend_network` | Network isolation, `backend` is the only service on both |
| `docker_volume` | `mongo_volume` | MongoDB data persistence (`mongo-data`) |
| `docker_image` | `mongodb-image`, `backend-image`, `frontend-image` | Images from Docker Hub (mongo) and from GHCR (backend/frontend) |
| `docker_container` | `mongodb`, `backend`, `frontend` | The three application services, with healthchecks, resource limits and dependencies |

Creation follows the order mongodb → backend → frontend, enforced via `depends_on`; each container waits for the one it depends on to reach `healthy` state (`wait = true` + `healthcheck` block), reproducing Docker Compose's `depends_on: condition: service_healthy` semantics:
```hcl
resource "docker_container" "mongodb" {
  # ...
  wait = true
  healthcheck {
    test         = ["CMD-SHELL", "mongosh --quiet -u $MONGO_INITDB_ROOT_USERNAME -p $MONGO_INITDB_ROOT_PASSWORD --authenticationDatabase admin --eval \"db.adminCommand('ping')\" || exit 1"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "20s"
  }
}
```

#### Key variables

| Name | Description | Default |
|---|---|---|
| `project_name` | Project prefix | `habit-tracker` |
| `github_user` | GHCR owner of backend/frontend images | `frapanca` |
| `backend`, `frontend` | Names/prefixes of the two application services | `backend`, `frontend` |
| `github_image_tag_backend`, `github_image_tag_frontend` | GHCR image tag | `v0.1.1` |
| `backend_port` | Backend internal port | `5000` |
| `frontend_port` | Host port mapped to frontend's 80 (validated between 1025 and 65534) | `8080` |
| `db_name` | MongoDB container name/hostname | `mongodb` |
| `mongo_image_name` | MongoDB Docker Hub image name | `mongo` |
| `mongodb_version` | MongoDB image tag | `7` |
| `mongo_root_username` | MongoDB root user | `admin` |
| `mongo_root_password` | MongoDB root password (**sensitive**) | `CHANGE_ME` - override this |
| `mongo_root_database` | Application database name | `habittracker` |

#### Available outputs

| Output | Content |
|---|---|
| `container_mongodb_id`, `container_backend_id`, `container_frontend_id` | Docker IDs of the three containers |
| `container_mongodb_name`, `container_backend_name`, `container_frontend_name` | Actual container names |
| `network_backend_name`, `network_frontend_name` | Names of the created Docker networks |
| `volume_name`, `volume_path` | MongoDB volume name and mountpoint |
| `access_url` | URL to reach the frontend from the host (`http://localhost:{frontend_port}`) |

#### Quick setup (Terraform - Local Docker)

```bash
cd terraform-docker
cp terraform.tfvars.example terraform.tfvars   # and fill in mongo_root_password

terraform init
terraform plan
terraform apply

terraform output access_url    # URL to reach the frontend
```

#### Useful commands

```bash
terraform fmt -recursive                # normalize formatting
terraform validate                      # static/syntax check
terraform output                        # show all outputs

terraform destroy                       # remove EVERYTHING, including the data volume
docker ps -a                            # verify no container is left
docker network ls                       # verify networks were removed
docker volume ls                        # verify the volume was removed
```

#### Technical notes

**GHCR authentication**: if the `backend`/`frontend` GHCR packages are private, `terraform apply` fails to pull them unless you authenticate beforehand with `docker login ghcr.io`, or add a `registry_auth` block in `provider "docker"` with a token stored in a `sensitive` variable.

**`wait` + `healthcheck` instead of `depends_on: condition`**: in the Docker provider, waiting for *healthy* state is declared on the resource being waited on (`wait = true` on the container you depend on), not on the dependent one: unlike Compose's syntax, where `condition: service_healthy` is written on the dependent service.

**Frontend healthcheck, `localhost` vs `127.0.0.1`**: on `nginx:alpine` with a custom `default.conf`, the init script does not enable the IPv6 listener; `wget http://localhost:80` can resolve to `::1` first and get connection refused even though nginx works fine over IPv4. The healthcheck therefore uses explicit `http://127.0.0.1:80` to avoid the DNS resolution ambiguity.

**`terraform destroy` and the data volume**: unlike `docker compose down` (which preserves volumes unless `-v` is added), `terraform destroy` *always* removes `docker_volume.mongo_volume` as well, data included. There is no default distinction between "state" and "persistent data" resources. Add `lifecycle { prevent_destroy = true }` to the resource to guard against accidental destruction.

**Secrets in state**: `mongo_root_password` is marked `sensitive = true` (hidden from plan/apply output), but it still sits in clear text inside the local `terraform.tfstate` file: acceptable for local use, worth revisiting with remote encrypted state or a secrets manager if the project moves to shared environments.

### Terraform - Shared

Resources shared between the EC2 (`terraform-aws/`) and EKS (`terraform-aws-eks/`) deployments, under `terraform-aws-shared/`: a Docker registry and the permissions the CD uses to publish images to it. Kept in a separate module because, unlike EC2 and EKS, there's never a good reason to destroy them: they're free to keep always on, and losing them would break the CI/CD pipeline and empty out the images available to both deployments.

#### Provider and versions

| Component | Version |
|---|---|
| Terraform | `>= 1.5.0` |
| Provider `hashicorp/aws` | `~> 5.0` |
| Provider `hashicorp/tls` | `~> 4.0` |

#### Managed resources

| Terraform resource | Name | Purpose |
|---|---|---|
| `aws_ecr_repository` | `backend_ecr_repo`, `frontend_ecr_repo` | Docker image registry, with scan on push |
| `aws_ecr_lifecycle_policy` | one per repository | Keeps only the last 5 images per repository |
| `aws_iam_openid_connect_provider` | GitHub Actions provider | OIDC trust toward `token.actions.githubusercontent.com`, for temporary AWS credentials in the CD |
| `aws_iam_role` + policy attachment | CD push role | Permission to publish images to ECR, assumable only by workflows running for a tag push on this repository |

#### Why it's separate from the other modules

Docker images and the CD's permission to publish them don't depend on *where* the app runs (EC2 or EKS): they're shared supporting infrastructure. Keeping them in a separate, always-applied module avoids two concrete problems hit during this project's development: losing the images every time `terraform-aws/` is destroyed to save on costs, and having to recreate the OIDC role from scratch (with a matching update to the GitHub repository variable) every time. `terraform-aws/` and `terraform-aws-eks/` don't reference these resources through Terraform (no `terraform_remote_state`): they're independent roots, and they reconstruct the registry URL from the account ID and the naming convention instead.

#### Setup

```bash
cd terraform-aws-shared
terraform init
terraform apply
```

No ongoing cost: empty ECR repositories and an IAM role generate no charges, this module can stay applied indefinitely.

#### Technical notes

**Immutable OIDC claim**: the trust policy's `sub` condition uses the `repo:OWNER@OWNER_ID/REPO@REPO_ID:ref:refs/tags/*` format, introduced by GitHub for repositories created after July 15, 2026 (see the `github_owner_id`/`github_repository_id` variables). A repository created before that date would use the older, names-only format.

### Terraform - AWS

Provisioning of the AWS infrastructure for the application's production deployment, under `terraform-aws/`: backend/frontend images (published to Amazon ECR, managed separately under `terraform-aws-shared/`, see above) run on an EC2 instance via Docker Compose, with credentials managed by Secrets Manager instead of plain environment variables.

#### Provider and versions

| Component | Version |
|---|---|
| Terraform | `>= 1.5.0` |
| Provider `hashicorp/aws` | `~> 5.0` |
| Provider `hashicorp/random` | `~> 3.6` |

#### Managed resources

| Terraform resource | Name | Purpose |
|---|---|---|
| `random_password` + `aws_secretsmanager_secret` | Mongo credentials | Generation and storage of MongoDB root credentials, never in plain text in the repo |
| `aws_security_group` | `habit-tracker-sg` | Port 80 open to everyone, port 22 restricted to a single IP |
| `aws_iam_role` + `aws_iam_instance_profile` | EC2 role | Minimal permissions: read only this project's Mongo secret, pull from ECR |
| `aws_key_pair` | SSH key | Imports the local public key for SSH access |
| `aws_instance` | application instance | Runs Docker Compose with the images from ECR, bootstrapped via `user_data` |

The ECR repositories and the CD's OIDC role aren't managed here: they live in `terraform-aws-shared/` (see above), applied independently. The image URL is reconstructed in `ec2.tf` from `data.aws_caller_identity.current.account_id` and the naming convention (`<account>.dkr.ecr.<region>.amazonaws.com/habit-tracker-<service>:<tag>`), not through a direct reference to a Terraform resource in this module.

The VPC and subnets used are the account's default ones (`data "aws_vpc"`, `data "aws_subnets"`), not created by this project.

#### Key variables

| Name | Description | Default |
|---|---|---|
| `aws_region` | AWS region | `eu-west-1` |
| `project_name` | Project prefix | `habit-tracker` |
| `instance_type` | EC2 instance type | `t3.micro` |
| `allowed_ssh_cidr` | CIDR authorized on port 22 (`IP/32` format) | none, required |
| `ssh_public_key_path` | Path to the local SSH public key | none, required |
| `app_repo_url` | Git URL cloned by the EC2 instance at boot | `https://github.com/FraPanca/Habit-Tracker.git` |
| `backend_image_tag`, `frontend_image_tag` | ECR image tags to deploy | none, required |

#### Available outputs

| Output | Content |
|---|---|
| `mongo_secret_arn` | ARN of the Mongo secret |
| `app_security_group_id` | Security group ID |
| `ec2_instance_profile_name` | IAM instance profile name |
| `ec2_public_ip`, `app_url` | Instance's public IP and URL to reach the app |

#### How the bootstrap works

On first boot (handled by `cloud-init` via `user_data`, run **only once**), the instance:
1. installs Docker and the Compose plugin (not included in Amazon Linux 2023's package repository)
2. clones this repository (public, no credentials needed)
3. logs in to ECR using the temporary credentials of the instance's IAM role
4. fetches Mongo credentials from Secrets Manager and writes a `.env` file inside the cloned folder
5. runs `docker compose -f docker-compose.aws.yml up -d`, which reuses the same two-network architecture as the local Compose setup but with `backend`/`frontend` as ECR `image:` references instead of `build:`

If you push code changes to GitHub after the instance is already running, the EC2 instance does not pick them up automatically, a redeploy is needed (see useful commands).

#### Quick setup (Terraform - AWS)

```bash
cd terraform-aws
# create terraform.tfvars with: allowed_ssh_cidr, ssh_public_key_path, backend_image_tag, frontend_image_tag

terraform init
terraform plan
terraform apply

terraform output app_url    # URL to reach the app
```

Building and pushing the images to ECR beforehand (not managed by Terraform):
```bash
aws ecr get-login-password --region eu-west-1 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-west-1.amazonaws.com

docker build -t habit-tracker-backend ./backend
docker tag habit-tracker-backend:latest <account-id>.dkr.ecr.eu-west-1.amazonaws.com/habit-tracker-backend:<tag>
docker push <account-id>.dkr.ecr.eu-west-1.amazonaws.com/habit-tracker-backend:<tag>
```
(same procedure for `frontend`)

#### Useful commands

```bash
terraform apply -replace="aws_instance.app"    # recreates only the EC2 instance (e.g. after a GitHub push), leaving the rest untouched
terraform destroy                              # removes the whole AWS infrastructure

aws ecr describe-images --repository-name habit-tracker-backend                          # list images in the repo
aws ecr describe-image-scan-findings --repository-name habit-tracker-frontend \
  --image-id imageTag=<tag>                                                              # security scan results

ssh -i ~/.ssh/habit-tracker-aws ec2-user@$(terraform output -raw ec2_public_ip)           # SSH access to the instance
sudo docker compose -f /opt/app/docker-compose.aws.yml ps                                # container status on the EC2 instance
sudo cat /var/log/cloud-init-output.log                                                  # bootstrap log, useful for debugging
```

#### Technical notes

**Registry separate from GHCR**: this deployment uses Amazon ECR, not GitHub Container Registry like the rest of the project. This is a deliberate choice for the exercise (end-to-end provisioning with native AWS services), not a technical requirement: the backend/frontend images stay identical, only where they're published changes.

**Docker Compose plugin on Amazon Linux 2023**: the AL2023 system repository's `docker` package only ships the engine, not the Compose v2 plugin. The `user_data` script downloads it as a binary from GitHub Releases and installs it under `/usr/local/lib/docker/cli-plugins/`.

**`user_data` runs only once**: unlike a CI/CD-based deployment (see above, for GHCR), there is no auto-pull mechanism for code or images after the first boot. An update requires either manual SSH access (`git pull` + `docker compose up -d --pull always`) or recreating the instance with `terraform apply -replace`.

**Secret in Secrets Manager, not only in state**: the password generated by `random_password` is written to Secrets Manager, from which the EC2 instance reads it at runtime with no static credentials. The Terraform state still contains the value in plain text (it's a Terraform resource like any other): the same warning about the local state file noted for `terraform-docker/` applies here too.

**Vulnerabilities in the frontend's base image**: ECR scanning flagged a few CVEs in the `util-linux` system package bundled in `nginx:alpine`, all with a local attack vector (they require an already active shell inside the container). The frontend container only exposes nginx, so the practical risk is considered low. Checked on 2026-09-11, worth rechecking on every base image rebuild.

**Costs**: ECR (500 MB-month free for the first 12 months of the account, then paid), Secrets Manager (not covered by the free tier, about $0.40/month per secret), EC2 t3.micro (free tier eligible for the first 12 months of the account). Run `terraform destroy` when done testing to bring costs back to zero.

### Kubernetes on AWS (EKS)

Alternative deployment on a real Kubernetes cluster on AWS, reusing the same Helm chart already validated on minikube (`charts/habit-tracker/`), with an independent Terraform root in `terraform-aws-eks/`.

#### Cost warning

Unlike everything else in this project, **EKS is not free even for a few minutes of testing**: the control plane costs about $0.10/hour regardless of usage, on top of the EC2 nodes and any load balancer. Keep it running only as long as needed for testing, and destroy right after (see the destroy order below, important).

#### Managed resources

| Resource | Purpose |
|---|---|
| `aws_iam_role` (cluster and nodes) | Roles required by EKS for the control plane and worker nodes |
| `aws_eks_cluster` | Control plane, on the default VPC's subnets |
| `aws_eks_access_entry` | Kubernetes permissions for the principal applying Terraform (modern API, not the legacy `aws-auth` ConfigMap) |
| `aws_eks_node_group` | Managed node group, 2 `t3.small` instances |
| `aws_iam_openid_connect_provider` (cluster) | The cluster's own OIDC issuer, for IRSA (IAM Roles for Service Accounts) |
| `aws_eks_addon` (aws-ebs-csi-driver) | EBS persistence driver, with a dedicated IAM role via IRSA |
| `kubernetes_storage_class` | Default `gp3` StorageClass (the addon alone doesn't create one on a standard node group) |
| `helm_release` (ingress-nginx) | Same Ingress controller used on minikube, here annotated for a Network Load Balancer instead of the default legacy Classic Load Balancer |
| `helm_release` (metrics-server) | Required by the chart's Horizontal Pod Autoscaler |
| `helm_release` (argocd) | Installs ArgoCD in the cluster, used for the application's GitOps deployment (see the "GitOps with ArgoCD" section below) |

#### `values-eks.yaml`

Chart overrides for EKS: `backend.image.repository`/`frontend.image.repository` point to the full ECR registry path instead of the bare name used for minikube's local images, `pullPolicy: IfNotPresent` instead of `Never` (the node actually needs to pull the image). Also sets `mongodb.auth.existingSecret`, used by the GitOps flow described below to reference a Secret created by hand in the cluster, instead of having the chart generate it.

#### Quick setup

```bash
cd terraform-aws-eks
terraform init
terraform apply    # 10-15 minutes, the cluster takes a while to become Active; this also bootstraps ArgoCD
```

From here on, the application is no longer deployed with a manual `helm install`, ArgoCD takes care of it: see the "GitOps with ArgoCD" section right below for the full steps (creating the namespace and the Mongo secret, registering the Application, checking the sync status).

End-to-end test once the app is in sync (no real domain configured, the Host header is passed explicitly):
```bash
kubectl get svc -n ingress-nginx
curl -H "Host: habit-tracker.local" http://<nlb-hostname>
```

#### Destroy: order matters

Unlike the other modules in this project, order matters here: the application is managed by ArgoCD (itself installed by Terraform), not by a direct `helm install` anymore, and Terraform manages three `helm_release` resources (ingress-nginx, metrics-server, argocd) inside the same cluster it's about to destroy.

```bash
kubectl delete -f argocd/application.yaml   # the finalizer cascade-deletes the resources, including mongodb's EBS volume

cd terraform-aws-eks
terraform destroy                            # uninstalls argocd/ingress-nginx/metrics-server, then cluster/nodes/IAM
```

Final check that nothing billable is left:
```bash
aws eks describe-cluster --name habit-tracker-cluster --region eu-west-1   # expected: ResourceNotFoundException
aws elbv2 describe-load-balancers --region eu-west-1 --query 'LoadBalancers[]'
aws ec2 describe-volumes --region eu-west-1 --filters Name=status,Values=available --query 'Volumes[].VolumeId'
```

#### Technical notes

**No automatic default StorageClass**: automatic gp3 StorageClass creation by the `aws-ebs-csi-driver` addon only applies to EKS Auto Mode. On a "standard" managed node group like this one, the addon installs only the driver: the StorageClass must be defined explicitly (see `kubernetes_storage_class.gp3_default`).

**Node sizing**: a single `t3.small` isn't enough to host the EBS CSI driver, ingress-nginx, metrics-server, and the whole application (mongodb, 2 backend replicas, frontend) at once: both available memory and the max pods per node are exhausted. The node group is configured with `node_desired_size = 2` for this reason. With ArgoCD added on top, the tighter constraint is no longer memory but the maximum number of pods per node, see the "GitOps with ArgoCD" section below for details.

**Legacy Classic Load Balancer by default**: without annotations, ingress-nginx's `LoadBalancer` Service would provision a Classic Load Balancer (the legacy "in-tree" controller, now in maintenance-only mode) instead of a Network Load Balancer. The `service.beta.kubernetes.io/aws-load-balancer-type: nlb` annotation on the `helm_release` fixes this without installing the full AWS Load Balancer Controller.

### GitOps with ArgoCD

The app's deployment on EKS no longer happens through a manual `helm install`/`helm upgrade`, ArgoCD keeps the cluster in sync with the state declared in the Helm chart (`charts/habit-tracker/`), read directly from this repository. It's the same Helm chart already used on minikube and on EKS in manual mode, just applied differently.

#### Flow

```
Terraform (terraform-aws-eks/)
   |
   v
EKS cluster + node group + ingress-nginx + metrics-server + ArgoCD (helm_release)
   |
   | kubectl apply, one time only
   v
ArgoCD Application (argocd/application.yaml)
   |
   | reads, on continuous polling
   v
This Git repository: charts/habit-tracker/ with values-eks.yaml
   |
   | applies, corrects drift, removes resources no longer present
   v
EKS cluster: habit-tracker namespace (mongodb, backend, frontend)
```

1. Terraform creates the EKS cluster, the node group, and installs via Helm (also from Terraform) `ingress-nginx`, `metrics-server`, and ArgoCD itself (`terraform-aws-eks/argocd.tf`).
2. One time only, the ArgoCD Application (`argocd/application.yaml`) is registered by hand with `kubectl apply`: this is the only manual step needed to start the automatic cycle.
3. From that point on, ArgoCD compares the desired state (`charts/habit-tracker` with `values-eks.yaml`) against the cluster's actual state, and:
   - automatically applies every change pushed to `main` (auto-sync)
   - automatically reverts any out-of-band manual change, such as a `kubectl scale` or `kubectl edit` (selfHeal)
   - removes resources no longer present in the chart (prune)

#### Secret management

MongoDB credentials are not in Git. The chart natively supports `mongodb.auth.existingSecret`: when set, `templates/secret.yaml` does not create any Secret, and the Deployments read the credentials from a Secret created by hand in the cluster, outside the GitOps cycle:

```bash
kubectl create namespace habit-tracker

kubectl create secret generic habit-tracker-mongodb-secret \
  -n habit-tracker \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD='<password>'
```

The namespace and the secret must be created before ArgoCD's first sync, otherwise pods stay in a configuration error until the Secret exists.

#### End-to-end setup

```bash
cd terraform-aws-eks
terraform apply

# ArgoCD's initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d

kubectl create namespace habit-tracker
kubectl create secret generic habit-tracker-mongodb-secret -n habit-tracker \
  --from-literal=MONGO_INITDB_ROOT_USERNAME=admin \
  --from-literal=MONGO_INITDB_ROOT_PASSWORD='<password>'

kubectl apply -f argocd/application.yaml
kubectl get application habit-tracker -n argocd   # expected: Synced / Healthy
```

Accessing the UI (optional):
```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
# https://localhost:8080, user admin, password retrieved above
```

At the end of the session, `terraform destroy` as described in the previous section (the EKS cluster is not covered by the free tier).

#### GitOps pull-based versus the previous push-based flow

| | Previous flow (manual `helm install`/`upgrade`, or `helm_release` in Terraform) | GitOps with ArgoCD |
|---|---|---|
| Who triggers the deploy | The developer, from a local machine, with AWS/kubeconfig credentials | ArgoCD, from inside the cluster |
| Credentials toward the cluster | Have to leave the cluster (kubeconfig, IAM) toward whoever runs the deploy | Stay inside the cluster, only ArgoCD has access |
| Desired state | Implicit: whatever was just run | Explicit and versioned: the chart in Git is the single source of truth |
| Manual drift (`kubectl edit`, `scale`, etc.) | Stays until someone redeploys | Detected and reverted automatically (selfHeal) |
| Rollback | `helm rollback` by hand, requires direct cluster access | `git revert` plus auto-sync, no direct access needed |
| Audit trail | Local/CI Helm history, not always centralized | Git history of the manifests, plus ArgoCD's own sync history |
| Initial bootstrap | Doesn't exist, the first deploy is already a push | Still exists: the first Application has to be applied by hand once, pull-based doesn't fully remove the initial push |

### Monitoring

Observability stack for the application, entirely local and free to run: application and infrastructure metrics, a dashboard versioned in the repository, and alerting tested end to end. Metrics tell you *what* is happening; to understand *why*, they are paired with [centralized logging](#centralized-logging-elk-stack).

Principles followed:

- **Everything is code**: Prometheus configuration, rules, alert routing, Grafana datasources and dashboard are files in the repository. No manual clicking in the UI: `docker compose down -v && up` recreates the exact same environment.
- **RED method** for the service (Rate, Errors, Duration) and saturation metrics for resources.
- **Tested alerts**: rules have unit tests run in CI with `promtool`, plus a manual chaos testing procedure.

#### Architecture

| Component | Role | Port (localhost only) |
|---|---|---|
| Prometheus | Collects metrics (pull), evaluates recording and alerting rules | 9090 |
| Alertmanager | Groups, deduplicates, inhibits and routes alerts | 9093 |
| Grafana | Dashboard provisioned from file | 3000 |
| cAdvisor | Container metrics: CPU, memory, network | internal |
| mongodb-exporter | MongoDB metrics: connections, operations | internal |
| alert-receiver | Local webhook that prints notifications to the logs | 5001 |

The stack adds a `monitoring-net` network, separate from the existing ones. The only two "bridge" containers are the backend (to expose `/metrics`) and the MongoDB exporter (which needs to reach the database). Prometheus and Grafana are not on `backend-net` and therefore have no direct access to the database.

The backend's `/metrics` endpoint is not exposed externally: nginx only forwards `/api/`, so the metrics are readable only from the internal network. All monitoring ports are published on `127.0.0.1`, not on the LAN.

#### Quick start

```bash
cp .env.example .env        # set MONGO_ROOT_PASSWORD and GRAFANA_ADMIN_PASSWORD

docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps

./monitoring/scripts/load-test.sh 300   # 5 minutes of traffic to populate the charts
```

| URL | What you find |
|---|---|
| http://localhost | The application |
| http://localhost:3000 | Grafana (the dashboard is the home) |
| http://localhost:9090/targets | Scrape status: all targets should be UP |
| http://localhost:9090/alerts | Alerting rules and their state |
| http://localhost:9093 | Alertmanager: active, silenced and inhibited alerts |
| http://localhost:5001/alerts | Latest notifications received by the webhook (JSON) |

To avoid repeating the two `-f` flags on every command:

```bash
export COMPOSE_FILE=docker-compose.yml:docker-compose.monitoring.yml
docker compose up -d
```

#### Metrics

**Application metrics (backend, `prom-client`)**

| Metric | Type | Labels | Use |
|---|---|---|---|
| `http_requests_total` | counter | `method`, `route`, `status_code` | Rate and errors |
| `http_request_duration_seconds` | histogram | `method`, `route`, `status_code` | Latency (percentiles, heatmap) |
| `habit_tracker_habits_created_total` | counter | | Business: habits created |
| `habit_tracker_entries_recorded_total` | counter | | Business: entries recorded |
| `nodejs_*`, `process_*` | various | | Heap, event loop lag, CPU (default metrics) |

Cardinality is kept under control: the `route` label holds the route template (`/api/habits/:id/entries`), never the real path with the IDs. Requests that match no route all end up under `route="unmatched"`. Without these two rules, every ID and every random URL hit by a scanner would create a new time series, growing Prometheus's memory without bound. This behaviour is covered by tests in `backend/tests/integration/metrics.test.js`.

Healthcheck (`/api/health`) and scrape (`/metrics`) requests are excluded from traffic metrics, so they do not skew the statistics.

**Recording rules**

Defined in `monitoring/prometheus/rules/recording.yml` and used by both the alerts and the dashboard: the colored threshold you see in Grafana is exactly the same expression that triggers the alert.

| Rule | Meaning |
|---|---|
| `job:http_requests:rate5m` | Requests per second (5 min average) |
| `job:http_requests_errors:ratio_rate5m` | Share of 5xx responses |
| `job:http_request_duration_seconds:p95_5m` | 95th percentile latency |
| `job:http_request_duration_seconds:p99_5m` | 99th percentile latency |

#### Dashboard as code

The dashboard lives in `monitoring/grafana/dashboards/habit-tracker.json` and is loaded at startup through provisioning (`monitoring/grafana/provisioning/`). Datasources are also provisioned with fixed `uid`s, so the dashboard does not depend on IDs generated at runtime.

Dashboard sections:

1. Overview: backend status, requests/s, error rate, p95 latency, active alerts.
2. HTTP traffic (RED): requests per route, responses by status code, latency percentiles, error rate per route, latency heatmap.
3. Business metrics: habits created and entries recorded.
4. Node.js runtime: V8 heap, event loop lag, process CPU.
5. Containers: CPU, memory relative to `mem_limit`, network traffic.
6. MongoDB: status, connections, operations per second.

Variables: `$route` and `$container` for filtering. Prometheus alerts show up as red annotations on the charts.

The dashboard cannot be edited from the UI (`allowUiUpdates: false`). To change it: duplicate it in Grafana, edit it, export the JSON (Share, Export), replace the file in the repository and open a PR. Grafana reloads the file within 30 seconds.

#### Alerting

| Alert | Condition | For | Severity |
|---|---|---|---|
| `BackendDown` | Backend scrape failed | 1m | critical |
| `MongoDBDown` | The exporter cannot reach MongoDB | 1m | critical |
| `MonitoringTargetDown` | Another target is not responding | 2m | warning |
| `HighErrorRate` | 5xx above 5% and traffic above 0.1 req/s | 2m | warning |
| `HighLatencyP95` | p95 above 500ms | 5m | warning |
| `NodeEventLoopLagHigh` | Event loop lag p99 above 200ms | 5m | warning |
| `ContainerMemoryNearLimit` | Working set above 90% of `mem_limit` | 5m | warning |

Design choices:

- The `for` field avoids notifications on spikes lasting only a few seconds (flapping).
- `HighErrorRate` requires a minimum amount of traffic: with two requests per minute, a single 5xx would already be 50%.
- Inhibit rules in Alertmanager: if MongoDB is down, the backend's 5xx responses are a symptom and are not notified. You get a single alert on the root cause, not a flood.
- The default receiver is a local webhook, so no external account or service is required. `alertmanager.yml` has a commented example for Telegram.

**Rule unit tests**

```bash
docker run --rm -v "$PWD/monitoring/prometheus:/etc/prometheus:ro" -w /etc/prometheus \
  --entrypoint promtool prom/prometheus:v3.13.3 test rules tests/alerts.test.yml
```

The tests in `monitoring/prometheus/tests/alerts.test.yml` simulate synthetic time series and check, for example, that `BackendDown` stays pending for the first minute and fires afterwards, that `HighErrorRate` does not fire with negligible traffic, and that `ContainerMemoryNearLimit` ignores containers without a limit. They run in CI on every change (`.github/workflows/monitoring.yml`), together with validation of compose, Prometheus, Alertmanager and the dashboard.

**End to end tests (chaos testing)**

In one terminal, follow the notifications:

```bash
docker compose -f docker-compose.yml -f docker-compose.monitoring.yml logs -f alert-receiver
```

Scenario 1, backend down:

```bash
./monitoring/scripts/chaos.sh backend-down
```

1. After about 15 to 30 seconds, on http://localhost:9090/alerts `BackendDown` is pending.
2. After one minute it moves to firing and alert-receiver prints `FIRING [critical] BackendDown`.
3. `./monitoring/scripts/chaos.sh restore`, after a few minutes `RESOLVED` arrives.

Scenario 2, database down (inhibition):

```bash
./monitoring/scripts/chaos.sh mongo-down
./monitoring/scripts/load-test.sh 300 5     # in another terminal: requests now fail with 500
```

1. `MongoDBDown` fires and is notified.
2. With traffic now failing, `HighErrorRate` also goes firing in Prometheus, but in Alertmanager it shows as inhibited and generates no notification: a single alert on the root cause.
3. `./monitoring/scripts/chaos.sh restore`.

#### Troubleshooting

| Problem | Solution |
|---|---|
| `cadvisor` target DOWN or empty container panels | On some hosts (e.g. Docker Desktop on macOS, WSL2) cAdvisor needs extra permissions: add `privileged: true` and `devices: ["/dev/kmsg"]` to the service |
| `mongodb` target UP but `mongodb_up` equals 0 | Wrong credentials in `.env`. If the password contains special characters (`@`, `:`, `/`) it needs to be URL-encoded in `MONGODB_URI` |
| Grafana login rejects the `.env` password | The admin password is applied only on the first startup: `docker volume rm habit-tracker_grafana-data` and restart |
| "No data" panels right after startup | The `rate` queries over 5-minute windows need a few scrapes: run `load-test.sh` and wait 1 to 2 minutes |
| Changes to rules or `prometheus.yml` | `curl -X POST http://localhost:9090/-/reload` (no container restart needed) |

#### Possible improvements

- A dedicated MongoDB user for the exporter with only the `clusterMonitor` role, instead of root credentials (least privilege).
- A real receiver (Telegram, Discord or email) with secrets mounted from a file.
- Explicit SLOs (e.g. 99% of requests under 300ms) with burn rate alerts.
- Logs and metrics on the same screen, by adding Elasticsearch as a Grafana datasource.
- Porting the stack to Kubernetes with `kube-prometheus-stack` and `ServiceMonitor`.

### Centralized logging (ELK stack)

Logging stack for the application, entirely local and free to run: backend and nginx logs are collected, normalized and made searchable in Kibana, with a dashboard versioned in the repository. It complements [Monitoring](#monitoring-1): metrics tell you *what* is happening, logs help you understand *why*.

Principles followed:

- **Everything is code**: Filebeat configuration, Logstash pipeline and Kibana dashboard are files in the repository, and the dashboard is recreated with a single import command.
- **Structured logs at the source**: the backend writes JSON, so parsing is trivial and robust. For nginx, which writes plain text, a grok pattern calibrated on its format is used.
- **Common schema**: both services end up in the indices with the same field names for HTTP status and method, so a single chart can cover both.
- **The application does not depend on the stack**: if ELK is off or failing, Habit Tracker works normally.

#### Architecture

```
backend (Winston, JSON) ──► backend-logs volume ─┐
                                                 ├─► Filebeat ──► Logstash ──► Elasticsearch ──► Kibana
frontend (nginx access log) ► nginx-logs volume ─┘  (collection)   (parsing)     (indexing)      (dashboard)
```

| Service | Role | Port (localhost only) | mem_limit / cpus |
|---|---|---|---|
| `filebeat` | Reads log files from the shared volumes (read-only) and forwards them to Logstash | none | 256m / 0.3 |
| `logstash` | Filters, normalizes and enriches events | none | 768m / 0.7 (JVM heap 256m) |
| `elasticsearch` | Indexes events (one index per day per service) | `127.0.0.1:9200` | 1g / 1.0 (JVM heap 512m) |
| `kibana` | Log exploration and dashboards | `127.0.0.1:5601` | 1g / 0.5 |

The four components must run the same version, controlled by the `ELASTIC_VERSION` variable (default `9.4.6`). The stack uses about 2 to 3 GB of RAM.

Why files on a shared volume instead of Filebeat's autodiscovery on Docker container logs: the latter requires mounting the Docker socket and Docker's internal paths, which differ between native Linux and Docker Desktop. With volumes the project behaves the same on any system.

Elasticsearch runs in `single-node` mode with security disabled: acceptable only locally, which is why all ports are bound to `127.0.0.1`.

#### Compose file, volumes and startup order

The stack lives in `docker-compose.logging.yml`, layered on top of `docker-compose.yml` (see [Optional stacks](#optional-stacks-add-ons)). The file:

- adds the four services and the `logging-net` network, which only they belong to
- defines the `backend-logs` and `nginx-logs` volumes and mounts them both on `backend` and `frontend` (read-write, through an override of the two services) and on Filebeat (read-only): backend and frontend share logs with Filebeat exclusively through volumes
- defines `es-data` (Elasticsearch indices, Kibana dashboards and data views) and `filebeat-data` (registry with the position reached in each file)

Without this file the application works identically: logs stay in the container's filesystem and on stdout.

Startup order is guaranteed by `depends_on` with `condition: service_healthy`:
```
elasticsearch (healthy) → kibana
elasticsearch (healthy) → logstash → filebeat
```

| Service | Healthcheck |
|---|---|
| `elasticsearch` | `curl` on `/_cluster/health?wait_for_status=yellow` |
| `kibana` | `curl` on `/api/status`, expecting `"level":"available"` |

`logstash` and `filebeat` have no healthcheck: Filebeat retries the connection to Logstash on its own until it is ready. The application does not depend on the stack: if Elasticsearch or Kibana fail to start, Habit Tracker keeps working.

#### Logs produced by the application

**Backend** (`backend/src/logger.js`, Winston): one JSON line per event, written both to a file (`/app/backend/logs/backend.log`, `backend-logs` volume) and to stdout (JSON with `NODE_ENV=production`, colored and readable format in development). A middleware in `app.js` records every request as `http_request`, with:

- the real `method` and `path`, and `route` with the route template (`/api/habits/:id/entries`), the same normalization used for Prometheus metrics, so charts do not fragment per ID
- `status` and `duration_ms`
- a level based on the status: `info` below 400, `warn` for 4xx, `error` for 5xx

Unhandled errors are recorded as `unhandled_error` with the stack trace. `/api/health` and `/metrics` do not produce log lines because they are registered before the middleware.

```json
{"duration_ms":14,"level":"info","message":"http_request","method":"GET","path":"/api/habits","route":"/api/habits","service":"habit-tracker-backend","status":200,"timestamp":"2026-09-28T08:23:05.308Z"}
```

**Frontend** (nginx): the access log is written in an explicit "combined" format (`log_format combined_log` in `frontend/nginx.conf`) to `/var/log/app-logs/nginx/access.log`, `nginx-logs` volume. The default stdout log stays active, so `docker compose logs frontend` works as before.

```
172.19.0.1 - - [28/Sep/2026:08:23:05 +0000] "GET /api/habits HTTP/1.1" 200 385 "-" "curl/8.14.1"
```

#### Pipeline

Filebeat (`elk/filebeat/filebeat.yml`) reads the two files with `filestream` inputs, adds the `fields.service` field (`backend` or `frontend`) and sends everything to Logstash on port 5044. The registry with the position reached in each file lives in the `filebeat-data` volume, so a restart does not resend logs already shipped.

Logstash (`elk/logstash/pipeline/logstash.conf`) applies different filters depending on the service:

| Service | Input format | Filters | Resulting fields |
|---|---|---|---|
| `backend` | JSON | `json`, `date`, `mutate rename` | `log.level`, `http.request.method`, `url.path`, `http.response.status_code`, `route`, `duration_ms` |
| `frontend` | text (combined) | `drop` of healthcheck lines, custom `grok`, `date` | `source.address`, `http.request.method`, `url.original`, `http.response.status_code`, `http.response.body.bytes`, `user_agent.original` |

Useful details:

- `@timestamp` is the time of the original event, not the time of ingestion.
- The original line stays available in `event.original`.
- Docker healthcheck requests (user-agent `Wget`, every 30 seconds) are dropped: they would skew the traffic charts.
- Temporary fields used during parsing live under `[@metadata]` and are not indexed.
- The `http.response.status_code` field has the same name and the same numeric type in both indices.
- nginx's `error.log` is not collected: it has a different format from the access log and would need a dedicated pattern.

Indices created: `habit-tracker-backend-YYYY.MM.dd` and `habit-tracker-frontend-YYYY.MM.dd`.

#### Getting started

Requirements: about 4 GB of free RAM for the ELK stack. On Linux, Elasticsearch also requires `vm.max_map_count` of at least 262144:

```bash
sysctl vm.max_map_count                          # if it is lower than 262144:
sudo sysctl -w vm.max_map_count=262144
echo "vm.max_map_count=262144" | sudo tee /etc/sysctl.d/99-elasticsearch.conf
```

Start and verify. The commands in this section assume `COMPOSE_FILE` is exported, because the stack's services exist only in the logging file:

```bash
export COMPOSE_FILE=docker-compose.yml:docker-compose.logging.yml
docker compose up -d --build
docker compose ps        # Elasticsearch and Kibana take 1-2 minutes to become healthy
```

Generate some traffic, including a few 4xx errors, and check that the indices fill up:

```bash
./monitoring/scripts/load-test.sh 60
curl -s -o /dev/null localhost/api/habits/id-non-valido/entries     # 400
curl -s -o /dev/null localhost/api/non-esiste                        # 404

curl -s "localhost:9200/_cat/indices?v"
```

You should see the two indices `habit-tracker-backend-*` and `habit-tracker-frontend-*` with a `docs.count` above zero. The `yellow` status of the indices is normal: they ask for a replica that a single-node cluster cannot assign.

| URL | What you find |
|---|---|
| http://localhost:5601 | Kibana |
| http://localhost:9200 | Elasticsearch API |

**Importing the dashboard.** The file `elk/kibana/habit-tracker-dashboard.ndjson` contains the dashboard and the data view. Import it once, with Kibana `healthy`:

```bash
curl -s -X POST "localhost:5601/api/saved_objects/_import?overwrite=true" \
  -H 'kbn-xsrf: true' --form file=@elk/kibana/habit-tracker-dashboard.ndjson
```

Look for `"success":true` in the response. Then open **Dashboards, Habit Tracker - Logging** and set the time range to "Last 1 hour".

#### Dashboard

![Kibana dashboard](screenshots/kibana-dashboard.png)

| Panel | Filter (KQL) | What it shows |
|---|---|---|
| Richieste nginx per status code | `fields.service : "frontend"` | Count over time, split by `http.response.status_code` |
| Log backend per livello | `fields.service : "backend"` | Breakdown by `log.level.keyword` (`info`, `warn`, `error`) |
| Latenza media per rotta (ms) | `fields.service : "backend"` | Average of `duration_ms` per `route.keyword` |
| Richieste per rotta | `fields.service : "backend"` | Count per `route.keyword` |

Requests to `/api/...` are recorded twice, once by nginx and once by the backend: that is why every panel filters by service. A count over the whole data view would count each request twice.

To group by text fields in Kibana, use the `.keyword` variant (`log.level.keyword`, `route.keyword`, `url.path.keyword`).

**Editing the dashboard.** Change it in Kibana, save, then export the file again and commit it:

```bash
curl -s -X POST "localhost:5601/api/saved_objects/_export" \
  -H 'kbn-xsrf: true' -H 'Content-Type: application/json' \
  -d '{"type":["dashboard"],"includeReferencesDeep":true}' \
  -o elk/kibana/habit-tracker-dashboard.ndjson
```

The export contains the dashboard object, which embeds the four panels, and the data view.

#### Checks and useful commands

```bash
curl -s "localhost:9200/_cat/indices?v"                                          # indices and document counts
curl -s "localhost:9200/habit-tracker-backend-*/_search?q=log.level:warn&size=1&pretty"   # a warn-level log
curl -s "localhost:9200/habit-tracker-*/_count?q=tags:*failure&pretty"           # 0 = no parsing failures

docker compose logs --tail=30 filebeat           # file reading and connection to Logstash
docker compose logs --tail=30 logstash           # pipeline startup and filter errors
docker compose restart logstash                  # after every change to logstash.conf (it does not reload by itself)
```

To delete old indices you must give the full names, because Elasticsearch rejects wildcard deletions by default:
```bash
curl -X DELETE "localhost:9200/habit-tracker-backend-2026.09.28,habit-tracker-frontend-2026.09.28"
```

#### Troubleshooting

| Problem | Solution |
|---|---|
| No `habit-tracker-*` index right after startup | Logstash takes about a minute to start the pipeline and Filebeat retries on its own. Wait, generate traffic and check `_cat/indices` again |
| Indices still missing after a few minutes | Check in order `docker compose logs logstash` and `docker compose logs filebeat`, and verify that Filebeat sees the files with `docker compose exec filebeat ls -l /logs/backend /logs/nginx` |
| Elasticsearch does not become `healthy` or keeps restarting | Check `vm.max_map_count` and available RAM. As a last resort raise `ES_JAVA_OPTS` and `mem_limit` in the compose file |
| Filebeat exits with a permission error on `filebeat.yml` | Filebeat requires the file to be owned by root: the service is already started with `--strict.perms=false`, make sure the command hasn't been removed |
| Documents tagged `_grokparsefailure` or `_jsonparsefailure` | A line does not match the expected format. Look at the document's `message` field and compare it with the pattern in `logstash.conf` |
| A field does not show up among Kibana's options (for example `route.keyword`) | There are no documents with that field in the selected time range yet. Generate traffic, widen the range and use "refresh fields list" in the data view settings |
| The imported dashboard is empty | Panels only show logs from the selected time range. Generate traffic and choose "Last 1 hour" |
| `no such service` error (for example `filebeat`) | The logging file is not included in the command: export `COMPOSE_FILE` as in the Getting started section, or add `-f docker-compose.logging.yml` |
| Error pulling the ELK images | Check that the version in `ELASTIC_VERSION` exists as a tag on `docker.elastic.co` |

#### Notes and limitations

- Elasticsearch security is disabled and ports are bound to `127.0.0.1`: a setup suited only to a local environment.
- Log files have no rotation and indices have no retention policy: a real environment would add Winston rotation and an ILM policy.
- Elasticsearch, Kibana, Logstash and Filebeat must share the same version, which is why it is controlled by a single variable (`ELASTIC_VERSION`, default `9.4.6`).
- The pipeline covers the Docker Compose deployment. In the Kubernetes, EKS and EC2 deployments the backend's JSON logs still go to stdout (`kubectl logs`, `docker logs`), but the ELK stack is not ported to those environments.
- The `es-data` volume also holds Kibana's dashboards and data views: to regenerate them just run the import again.

#### Possible improvements

- Backend log rotation (`maxsize` and `maxFiles` on Winston's `File` transport) and an ILM policy for index retention.
- Collecting nginx's `error.log` with a dedicated input and pattern.
- Authentication and TLS on Elasticsearch and Kibana.
- Correlating metrics and logs in Grafana, with Elasticsearch as a datasource.
- Porting to Kubernetes with Filebeat as a DaemonSet.