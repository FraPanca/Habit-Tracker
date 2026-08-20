require('dotenv').config();
const connectDB = require('./db');
const app = require('./app');


connectDB();

const PORT = process.env.PORT || 5000;
app.listen(PORT, () => console.log(`Server avviato sulla porta ${PORT}`));