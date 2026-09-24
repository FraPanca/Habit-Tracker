/**
 * Receiver webhook minimale per Alertmanager.
 * - POST /alerts  -> riceve le notifiche e le stampa nei log in forma leggibile
 * - GET  /alerts  -> ultime 50 notifiche ricevute (JSON), utile per debug e screenshot
 * - GET  /health  -> healthcheck
 * Nessuna dipendenza esterna: solo il modulo http di Node.
 */
const http = require('node:http');

const PORT = Number(process.env.PORT) || 5001;
const MAX_HISTORY = 50;
const history = [];

function logAlert(alert) {
  const status = alert.status === 'firing' ? '🔥 FIRING  ' : '✅ RESOLVED';
  const { alertname, severity = 'n/a' } = alert.labels;
  const summary = alert.annotations?.summary ?? '';
  const when = alert.status === 'firing' ? alert.startsAt : alert.endsAt;
  console.log(`${status} [${severity}] ${alertname} - ${summary} (${when})`);
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end('{"status":"ok"}');
  }

  if (req.method === 'GET' && req.url === '/alerts') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify(history, null, 2));
  }

  if (req.method === 'POST' && req.url === '/alerts') {
    let body = '';
    req.on('data', (chunk) => {
      body += chunk;
      if (body.length > 1e6) req.destroy(); // protezione da payload anomali
    });
    req.on('end', () => {
      try {
        const payload = JSON.parse(body);
        payload.alerts.forEach(logAlert);
        history.unshift({ receivedAt: new Date().toISOString(), ...payload });
        history.length = Math.min(history.length, MAX_HISTORY);
        res.writeHead(200);
        res.end();
      } catch (err) {
        console.error('Payload non valido:', err.message);
        res.writeHead(400);
        res.end();
      }
    });
    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(PORT, () => console.log(`alert-receiver in ascolto sulla porta ${PORT}`));

process.on('SIGTERM', () => server.close(() => process.exit(0)));