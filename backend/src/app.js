const express = require('express');
const cors = require('cors');
const habitsRouter = require('./routes/habitsRoute');

const app = express();
app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));
app.use('/api/habits', habitsRouter);


module.exports = app;