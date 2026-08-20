const mongoose = require('mongoose');


async function connectDB() {
    try {
        await mongoose.connect(process.env.MONGO_URI);
        console.log('MongoDB connesso');
    } catch (err) {
        console.error('Errore connessione MongoDB: ', err.message);
        process.exit(1);
    }
}


module.exports = connectDB;