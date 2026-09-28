const express = require('express');
const cors = require('cors');
const habitsRouter = require('./routes/habitsRoute');
const { register, metricsMiddleware, tagRouteBase, routeLabel } = require('./metrics');
const logger = require('./logger');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use(metricsMiddleware);

app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const level = res.statusCode >= 500 ? 'error'
                : res.statusCode >= 400 ? 'warn'
                : 'info';
    logger.log(level, 'http_request', {
      method: req.method,
      path: req.originalUrl,
      route: routeLabel(req, res),
      status: res.statusCode,
      duration_ms: Date.now() - start,
    });
  });
  next();
});

app.use('/api/habits', tagRouteBase, habitsRouter);

app.use((err, req, res, next) => {
  if (err.name === 'CastError') {
    return res.status(400).json({ error: `ID non valido: ${err.value}` });
  }
  logger.error('unhandled_error', { message: err.message, stack: err.stack });
  res.status(500).json({ error: 'Errore interno del server' });
});


module.exports = app;