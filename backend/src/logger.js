const winston = require('winston');
const path = require('path');

const LOG_DIR = process.env.LOG_DIR || path.join(__dirname, '..', 'logs');

const jsonFormat = winston.format.combine(
  winston.format.timestamp(),
  winston.format.errors({ stack: true }),
  winston.format.json()
);

const logger = winston.createLogger({
  level: process.env.LOG_LEVEL || 'info',
  format: jsonFormat,
  defaultMeta: { service: 'habit-tracker-backend' },
  transports: [
    new winston.transports.File({ filename: path.join(LOG_DIR, 'backend.log') }),
  ],
});

// stdout: leggibile in dev, JSON in produzione (così "docker compose logs" resta coerente con il file)
logger.add(new winston.transports.Console({
  format: process.env.NODE_ENV === 'production'
    ? jsonFormat
    : winston.format.combine(winston.format.colorize(), winston.format.simple()),
}));

module.exports = logger;