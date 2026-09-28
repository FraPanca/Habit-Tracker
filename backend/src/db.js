const mongoose = require('mongoose');
const logger = require('./logger');

async function connectDB() {
    try {
        await mongoose.connect(process.env.MONGO_URI);
        logger.info('MongoDB connesso');
    } catch (err) {
        logger.error('Errore connessione MongoDB', { error: err.message });
        process.exit(1);
    }
}


module.exports = connectDB;