const mongoose = require('mongoose');

const habitSchema = new mongoose.Schema({
    name: { type: String, required: true, trim: true },
    type: { type: String, enum: ['boolean', 'numeric'], required: true },
    targetValue: { type: Number },
    createdAt: { type: Date, default: Date.now }
});


module.exports = mongoose.model('Habit', habitSchema);