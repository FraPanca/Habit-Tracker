const client = require('prom-client');

const register = new client.Registry();
register.setDefaultLabels({ app: 'habit-tracker-backend' });
client.collectDefaultMetrics({ register });

// --- Metriche HTTP (RED: Rate, Errors, Duration) ---

const httpRequestCounter = new client.Counter({
  name: 'http_requests_total',
  help: 'Numero totale di richieste HTTP',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Durata delle richieste HTTP',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.01, 0.05, 0.1, 0.3, 0.5, 1, 2, 5],
  registers: [register],
});

// --- Metriche di business ---

const habitsCreatedCounter = new client.Counter({
  name: 'habit_tracker_habits_created_total',
  help: 'Numero totale di abitudini create',
  registers: [register],
});

const entriesRecordedCounter = new client.Counter({
  name: 'habit_tracker_entries_recorded_total',
  help: 'Numero totale di entry giornaliere registrate o aggiornate',
  registers: [register],
});


function tagRouteBase(req, res, next) {
  res.locals.routeBase = req.baseUrl;
  next();
}

function routeLabel(req, res) {
  if (!req.route) return 'unmatched';
  const full = `${res.locals.routeBase ?? ''}${req.route.path}`;
  // "/api/habits/" -> "/api/habits" (la route "/" del router non lascia lo slash finale)
  return full.length > 1 ? full.replace(/\/$/, '') : full;
}

function metricsMiddleware(req, res, next) {
  const end = httpRequestDuration.startTimer();
  res.on('finish', () => {
    const labels = {
      method: req.method,
      route: routeLabel(req, res),
      status_code: String(res.statusCode),
    };
    httpRequestCounter.inc(labels);
    end(labels);
  });
  next();
}

module.exports = {
  register,
  metricsMiddleware,
  tagRouteBase,
  habitsCreatedCounter,
  entriesRecordedCounter,
};