require('dotenv').config();
const connectDB = require('./db');
const app = require('./app');
const logger = require('./logger');

connectDB();

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => logger.info(`Server avviato sulla porta ${PORT}`));