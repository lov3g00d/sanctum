import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import express from 'express';
import client from 'prom-client';

const register = new client.Registry();
client.collectDefaultMetrics({ register });

const httpRequestsTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request latency in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

function log(level, message, extra = {}) {
  process.stdout.write(
    `${JSON.stringify({ ts: new Date().toISOString(), level, service: 'nimbus-orders-api', message, ...extra })}\n`,
  );
}

// Stubs a database dependency. A real deploy would ping RDS here.
let dependencyReady = true;
async function checkDependency() {
  return dependencyReady;
}

export function createApp() {
  const app = express();
  app.disable('x-powered-by');
  app.use(express.json());

  app.use((req, res, next) => {
    const end = httpRequestDuration.startTimer();
    res.on('finish', () => {
      // Label with the matched route pattern, and a constant for unmatched
      // paths, so a 404 flood cannot blow up metric cardinality.
      const route = req.route?.path ?? 'unmatched';
      const labels = { method: req.method, route, status_code: String(res.statusCode) };
      httpRequestsTotal.inc(labels);
      end(labels);
    });
    next();
  });

  app.get('/healthz', (_req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  app.get('/readyz', async (_req, res) => {
    const ready = await checkDependency();
    if (ready) {
      res.status(200).json({ status: 'ready' });
    } else {
      res.status(503).json({ status: 'not_ready' });
    }
  });

  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  const orders = new Map();

  app.get('/v1/orders', (_req, res) => {
    res.json({ orders: [...orders.values()] });
  });

  app.post('/v1/orders', (req, res) => {
    const { sku, quantity } = req.body ?? {};
    if (typeof sku !== 'string' || !Number.isInteger(quantity) || quantity <= 0) {
      res.status(400).json({ error: 'sku (string) and quantity (positive integer) are required' });
      return;
    }
    const order = { id: randomUUID(), sku, quantity, createdAt: new Date().toISOString() };
    orders.set(order.id, order);
    res.status(201).json(order);
  });

  return app;
}

export function setDependencyReady(value) {
  dependencyReady = value;
}

function start() {
  const port = Number(process.env.PORT ?? 3000);
  const app = createApp();
  const server = createServer(app);

  server.listen(port, () => log('info', 'listening', { port }));

  const shutdown = (signal) => {
    log('info', 'shutdown initiated', { signal });
    // Fail readiness first so load balancers drain this instance before close.
    dependencyReady = false;
    server.close(() => {
      log('info', 'shutdown complete');
      process.exit(0);
    });
    setTimeout(() => {
      log('warn', 'forced shutdown after timeout');
      process.exit(1);
    }, 10_000).unref();
  };

  process.on('SIGTERM', () => shutdown('SIGTERM'));
  process.on('SIGINT', () => shutdown('SIGINT'));
}

if (process.argv[1] === new URL(import.meta.url).pathname) {
  start();
}
