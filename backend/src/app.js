const express = require('express');
const cors = require('cors');
const habitsRouter = require('./routes/habitsRoute');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));
app.use('/api/habits', habitsRouter);

app.use((err, req, res, next) => {
  if (err.name === 'CastError') {
    return res.status(400).json({ error: `ID non valido: ${err.value}` });
  }
  console.error(err);
  res.status(500).json({ error: 'Errore interno del server' });
});


module.exports = app;