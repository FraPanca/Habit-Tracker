const express = require('express');
const router = express.Router();
const Habit = require('../models/Habit');
const Entry = require('../models/Entry');


// Crea una nuova abitudine
router.post('/', async (req, res) => {
  try {
    const habit = await Habit.create(req.body);
    res.status(201).json(habit);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// Lista tutte le abitudini
router.get('/', async (req, res) => {
  const habits = await Habit.find().sort({ createdAt: -1 });
  res.json(habits);
});

// Elimina un'abitudine (e le sue entry)
router.delete('/:id', async (req, res) => {
  await Habit.findByIdAndDelete(req.params.id);
  await Entry.deleteMany({ habitId: req.params.id });
  res.status(204).send();
});

// Registra/aggiorna il valore di un giorno per un'abitudine
router.post('/:id/entries', async (req, res) => {
  const { date, value } = req.body;
  try {
    const entry = await Entry.findOneAndUpdate(
      { habitId: req.params.id, date },
      { value, notedAt: new Date() },
      { upsert: true, new: true }
    );
    res.status(201).json(entry);
  } catch (err) {
    res.status(400).json({ error: err.message });
  }
});

// Storico entry di un'abitudine (con filtro opzionale per range date)
router.get('/:id/entries', async (req, res) => {
  const { from, to } = req.query;
  const filter = { habitId: req.params.id };
  if (from || to) {
    filter.date = {};
    if (from) filter.date.$gte = from;
    if (to) filter.date.$lte = to;
  }
  const entries = await Entry.find(filter).sort({ date: 1 });
  res.json(entries);
});


module.exports = router;