const express = require('express');
const cors = require('cors');
const habitsRouter = require('./routes/habitsRoute');
const { register, metricsMiddleware } = require('./metrics');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

app.get('/metrics', async (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.use(metricsMiddleware);

app.use('/api/habits', habitsRouter);

app.use((err, req, res, next) => {
  if (err.name === 'CastError') {
    return res.status(400).json({ error: `ID non valido: ${err.value}` });
  }
  console.error(err);
  res.status(500).json({ error: 'Errore interno del server' });
});


module.exports = app;