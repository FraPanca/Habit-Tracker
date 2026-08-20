const mongoose = require('mongoose');

const entrySchema = new mongoose.Schema({
    habitId: { type: mongoose.Schema.Types.ObjectId, ref: 'Habit', required: true },
    date: { type: String, required: true }, // formato "YYYY-MM-DD"
    value: {
      type: mongoose.Schema.Types.Mixed,
      required: true,
      validate: {
        validator: (v) => typeof v === 'boolean' || typeof v === 'number',
        message: props => `${props.value} non è un valore valido: atteso booleano o numero`
      }
    },
    notedAt: { type: Date, default: Date.now }
});


entrySchema.index({ habitId: 1, date: 1 }, { unique: true });


module.exports = mongoose.model('Entry', entrySchema);