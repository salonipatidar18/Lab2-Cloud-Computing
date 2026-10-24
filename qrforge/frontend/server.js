/**
 * QRForge - Production QR Code Generator Server
 * ================================================
 * Two-tier architecture: this Express server handles:
 *  - Static file serving (public/)
 *  - QR generation with Redis caching
 *  - Prometheus metrics exposition
 *  - Health/readiness probes for Kubernetes
 *
 * Environment Variables:
 *   REDIS_HOST     - Redis hostname (default: localhost)
 *   REDIS_PORT     - Redis port    (default: 6379)
 *   PORT           - HTTP listen port (default: 3000)
 *   LOG_LEVEL      - Logging verbosity: silent|error|info (default: silent)
 *   NODE_ENV       - production|development
 */

'use strict';

const os = require('os');
const crypto = require('crypto');
const path = require('path');
const fs = require('fs');

const express = require('express');
const helmet = require('helmet');
const compression = require('compression');
const rateLimit = require('express-rate-limit');
const QRCode = require('qrcode');
const Redis = require('ioredis');
const promClient = require('prom-client');

// ─────────────────────────────────────────────────────────────
// Configuration
// ─────────────────────────────────────────────────────────────
const PORT       = parseInt(process.env.PORT || '3000', 10);
const REDIS_HOST = process.env.REDIS_HOST || 'localhost';
const REDIS_PORT = parseInt(process.env.REDIS_PORT || '6379', 10);
const LOG_LEVEL  = process.env.LOG_LEVEL || 'silent';
const HOSTNAME   = os.hostname();

const MAX_SIZE   = 2048;
const MIN_SIZE   = 128;
const MAX_N      = 30;   // max QR codes per /api/heavy request
const CACHE_TTL  = 3600; // seconds
const HISTORY_MAX = 50;

// Simple logger controlled by LOG_LEVEL
const log = {
  info:  (...a) => LOG_LEVEL === 'info'  && console.log('[INFO]',  ...a),
  error: (...a) => LOG_LEVEL !== 'silent' && console.error('[ERROR]', ...a),
};

// ─────────────────────────────────────────────────────────────
// Load templates
// ─────────────────────────────────────────────────────────────
const TEMPLATES = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'templates.json'), 'utf8')
);
const TEMPLATE_MAP = Object.fromEntries(TEMPLATES.map(t => [t.id, t]));

// ─────────────────────────────────────────────────────────────
// Redis client (ioredis with automatic reconnect)
// ─────────────────────────────────────────────────────────────
let redisReady = false;

const redis = new Redis({
  host: REDIS_HOST,
  port: REDIS_PORT,
  maxRetriesPerRequest: null,        // important: don't fail immediately
  enableReadyCheck: true,
  retryStrategy: (times) => {
    const delay = Math.min(times * 200, 5000);
    log.info(`Redis retry #${times} in ${delay}ms`);
    return delay;
  },
  reconnectOnError: () => true,
  lazyConnect: false,
});

redis.on('ready',  () => { redisReady = true;  log.info('Redis ready'); });
redis.on('close',  () => { redisReady = false; log.info('Redis closed'); });
redis.on('error',  (e) => { redisReady = false; log.error('Redis error:', e.message); });

// ─────────────────────────────────────────────────────────────
// Prometheus metrics
// ─────────────────────────────────────────────────────────────
const register = new promClient.Registry();
promClient.collectDefaultMetrics({ register, prefix: 'qrforge_process_' });

const httpRequestsTotal = new promClient.Counter({
  name: 'http_requests_total',
  help: 'Total HTTP requests by method, route, and status code',
  labelNames: ['method', 'route', 'status'],
  registers: [register],
});

const httpRequestDuration = new promClient.Histogram({
  name: 'http_request_duration_seconds',
  help: 'HTTP request duration in seconds',
  labelNames: ['method', 'route', 'status'],
  // Buckets tuned for P95 computation: fine-grained low end, coarser high end
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5, 10, 30],
  registers: [register],
});

const qrGeneratedTotal = new promClient.Counter({
  name: 'qr_generated_total',
  help: 'Total QR codes generated (cache misses only)',
  labelNames: ['template', 'format'],
  registers: [register],
});

const cacheHitsTotal = new promClient.Counter({
  name: 'cache_hits_total',
  help: 'Redis cache hits',
  registers: [register],
});

const cacheMissesTotal = new promClient.Counter({
  name: 'cache_misses_total',
  help: 'Redis cache misses (actual QR generations)',
  registers: [register],
});

// ─────────────────────────────────────────────────────────────
// Express app
// ─────────────────────────────────────────────────────────────
const app = express();

// Security headers (relaxed CSP for inline scripts/styles in the SPA)
app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      scriptSrc:  ["'self'", "'unsafe-inline'"],
      styleSrc:   ["'self'", "'unsafe-inline'", 'https://fonts.googleapis.com'],
      fontSrc:    ["'self'", 'https://fonts.gstatic.com'],
      imgSrc:     ["'self'", 'data:', 'blob:'],
      connectSrc: ["'self'"],
    },
  },
  crossOriginEmbedderPolicy: false,
}));

app.use(compression());
app.use(express.json({ limit: '100kb' }));
app.use(express.urlencoded({ extended: false, limit: '100kb' }));

// ── Prometheus timing middleware (no per-request console logging) ──
app.use((req, res, next) => {
  const start = process.hrtime.bigint();
  res.on('finish', () => {
    const route = req.route?.path || req.path.replace(/\/[0-9a-f-]{8,}/gi, '/:id') || 'unknown';
    const dur   = Number(process.hrtime.bigint() - start) / 1e9;
    const labels = { method: req.method, route, status: String(res.statusCode) };
    httpRequestsTotal.inc(labels);
    httpRequestDuration.observe(labels, dur);
  });
  next();
});

// Rate limiter — generous limits, won't block the load test
const apiLimiter = rateLimit({
  windowMs: 60_000,
  max: 2000,
  standardHeaders: true,
  legacyHeaders: false,
  skip: (req) => req.path === '/healthz' || req.path === '/readyz' || req.path === '/metrics',
});
app.use('/api', apiLimiter);

// Static files
app.use(express.static(path.join(__dirname, 'public')));

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

/**
 * Build the QRCode options object from request parameters.
 * Merges template defaults with per-request overrides.
 */
function buildQROptions({ template, size, fg, bg, ecc, format }) {
  const tmpl = TEMPLATE_MAP[template] || TEMPLATES[0];
  return {
    errorCorrectionLevel: ecc  || tmpl.ecc || 'M',
    margin:               tmpl.margin ?? 3,
    width:                Math.min(Math.max(parseInt(size, 10) || 512, MIN_SIZE), MAX_SIZE),
    color: {
      dark:  fg || tmpl.fg,
      light: bg || tmpl.bg,
    },
    type: format === 'svg' ? 'svg' : 'png',
  };
}

/** Compute a deterministic cache key from QR parameters */
function cacheKey(params) {
  const stable = JSON.stringify({
    type:     params.type,
    data:     params.data,
    template: params.template,
    size:     params.size,
    fg:       params.fg,
    bg:       params.bg,
    ecc:      params.ecc,
    format:   params.format,
  });
  return 'qr:' + crypto.createHash('sha256').update(stable).digest('hex');
}

/** Generate QR and return Buffer (PNG) or string (SVG) */
async function generateQR(data, opts) {
  if (opts.type === 'svg') {
    return QRCode.toString(data, { ...opts, type: 'svg' });
  }
  // Generates PNG buffer — large sizes are CPU-intensive (good for HPA demo)
  return QRCode.toBuffer(data, opts);
}

/** Push to the recent history list in Redis (fire-and-forget) */
function recordHistory(entry) {
  if (!redisReady) return;
  const key = 'history:recent';
  redis.lpush(key, JSON.stringify(entry)).catch(() => {});
  redis.ltrim(key, 0, HISTORY_MAX - 1).catch(() => {});
}

/** Increment per-template usage counter */
function incTemplateUsage(templateId) {
  if (!redisReady) return;
  redis.hincrby('stats:templates', templateId, 1).catch(() => {});
  redis.incr('stats:total').catch(() => {});
}

/** Build the QR data string depending on input type */
function buildQRData(type, body) {
  switch (type) {
    case 'url':   return body.data || '';
    case 'text':  return body.data || '';
    case 'wifi':
      return `WIFI:T:${body.encryption || 'WPA'};S:${body.ssid || ''};P:${body.password || ''};;`;
    case 'email':
      return `mailto:${body.email || ''}?subject=${encodeURIComponent(body.subject || '')}&body=${encodeURIComponent(body.body || '')}`;
    case 'phone':
      return `tel:${body.phone || ''}`;
    case 'vcard': {
      const v = body;
      return [
        'BEGIN:VCARD', 'VERSION:3.0',
        `FN:${v.name || ''}`,
        `ORG:${v.org || ''}`,
        `TEL:${v.phone || ''}`,
        `EMAIL:${v.email || ''}`,
        `URL:${v.url || ''}`,
        'END:VCARD',
      ].join('\n');
    }
    default: return body.data || '';
  }
}

// ─────────────────────────────────────────────────────────────
// API Routes
// ─────────────────────────────────────────────────────────────

/**
 * POST /api/qr
 * Body: { type, data, template, size, fg, bg, ecc, format, ...typeSpecific }
 * Returns: QR image (PNG binary or SVG text)
 */
app.post('/api/qr', async (req, res) => {
  try {
    const { type = 'url', template, size, fg, bg, ecc, format = 'png' } = req.body;

    const qrData = buildQRData(type, req.body);
    if (!qrData || qrData.length < 1) {
      return res.status(400).json({ error: 'No data provided for QR code' });
    }
    if (qrData.length > 2000) {
      return res.status(400).json({ error: 'Data too long (max 2000 chars)' });
    }

    const opts = buildQROptions({ template, size, fg, bg, ecc, format });
    const key  = cacheKey({ type, data: qrData, template, size: opts.width, fg: opts.color.dark, bg: opts.color.light, ecc: opts.errorCorrectionLevel, format });

    // ── Cache lookup ──
    if (redisReady) {
      const cached = await redis.getBuffer(key).catch(() => null);
      if (cached) {
        cacheHitsTotal.inc();
        await redis.hincrby('stats:cache', 'hits', 1).catch(() => {});
        res.setHeader('X-Cache', 'HIT');
        res.setHeader('X-Pod', HOSTNAME);
        if (format === 'svg') {
          res.setHeader('Content-Type', 'image/svg+xml');
          return res.send(cached.toString('utf8'));
        }
        res.setHeader('Content-Type', 'image/png');
        return res.send(cached);
      }
    }

    // ── Cache miss — generate ──
    cacheMissesTotal.inc();
    await redis.hincrby('stats:cache', 'misses', 1).catch(() => {});

    const result = await generateQR(qrData, opts);
    qrGeneratedTotal.inc({ template: template || 'default', format });

    // Store in Redis
    if (redisReady) {
      const buf = Buffer.isBuffer(result) ? result : Buffer.from(result, 'utf8');
      redis.set(key, buf, 'EX', CACHE_TTL).catch(() => {});
    }

    recordHistory({
      type,
      template: template || 'minimal-mono',
      size: opts.width,
      format,
      ts: Date.now(),
      preview: qrData.substring(0, 80),
    });
    incTemplateUsage(template || 'minimal-mono');

    res.setHeader('X-Cache', 'MISS');
    res.setHeader('X-Pod', HOSTNAME);
    if (format === 'svg') {
      res.setHeader('Content-Type', 'image/svg+xml');
      return res.send(result);
    }
    res.setHeader('Content-Type', 'image/png');
    return res.send(result);

  } catch (err) {
    log.error('QR generation error:', err.message);
    res.status(500).json({ error: 'QR generation failed', detail: err.message });
  }
});

/** GET /api/templates */
app.get('/api/templates', (_req, res) => {
  res.setHeader('X-Pod', HOSTNAME);
  res.json(TEMPLATES);
});

/** GET /api/history - last 10 generated QR entries */
app.get('/api/history', async (_req, res) => {
  res.setHeader('X-Pod', HOSTNAME);
  if (!redisReady) return res.json([]);
  try {
    const items = await redis.lrange('history:recent', 0, 9);
    res.json(items.map(i => {
      try { return JSON.parse(i); } catch { return null; }
    }).filter(Boolean));
  } catch {
    res.json([]);
  }
});

/** GET /api/stats */
app.get('/api/stats', async (_req, res) => {
  res.setHeader('X-Pod', HOSTNAME);
  if (!redisReady) return res.json({ total: 0, templates: {}, cache: { hits: 0, misses: 0 } });
  try {
    const [total, templates, cache] = await Promise.all([
      redis.get('stats:total'),
      redis.hgetall('stats:templates'),
      redis.hgetall('stats:cache'),
    ]);
    res.json({
      total: parseInt(total || '0', 10),
      templates: templates || {},
      cache: {
        hits:   parseInt(cache?.hits   || '0', 10),
        misses: parseInt(cache?.misses || '0', 10),
      },
    });
  } catch {
    res.json({ total: 0, templates: {}, cache: { hits: 0, misses: 0 } });
  }
});

/**
 * GET /api/heavy?size=2000&n=20
 * CPU-intensive endpoint for HPA load testing — generates n QR codes without caching.
 * Size and n are capped to safe maximums.
 */
app.get('/api/heavy', async (req, res) => {
  const size = Math.min(parseInt(req.query.size, 10) || 1024, MAX_SIZE);
  const n    = Math.min(parseInt(req.query.n,    10) || 5,    MAX_N);
  const data = req.query.data || 'https://qrforge.example.com/load-test-' + Date.now();

  const opts = {
    errorCorrectionLevel: 'H',
    margin: 2,
    width:  size,
    color:  { dark: '#000000', light: '#ffffff' },
  };

  try {
    const results = [];
    for (let i = 0; i < n; i++) {
      const buf = await QRCode.toBuffer(data + '-' + i, opts);
      results.push(buf.length);
      qrGeneratedTotal.inc({ template: 'heavy', format: 'png' });
    }
    res.setHeader('X-Pod', HOSTNAME);
    res.json({ generated: n, size, byteSizes: results, pod: HOSTNAME });
  } catch (err) {
    log.error('Heavy endpoint error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

/** GET /api/pod — returns pod hostname for load-balancing demo */
app.get('/api/pod', (_req, res) => {
  res.json({ hostname: HOSTNAME, pid: process.pid });
});

// ─────────────────────────────────────────────────────────────
// Health probes
// ─────────────────────────────────────────────────────────────

/** GET /healthz — Liveness probe: always 200 if process is alive */
app.get('/healthz', (_req, res) => {
  res.status(200).json({ status: 'alive', hostname: HOSTNAME });
});

/**
 * GET /readyz — Readiness probe: 200 only if Redis PING succeeds.
 * Kubernetes will remove the pod from the LB endpoint set if this returns non-2xx.
 */
app.get('/readyz', async (_req, res) => {
  if (!redisReady) {
    return res.status(503).json({ status: 'not ready', reason: 'Redis not connected' });
  }
  try {
    await redis.ping();
    res.status(200).json({ status: 'ready', hostname: HOSTNAME });
  } catch (err) {
    res.status(503).json({ status: 'not ready', reason: err.message });
  }
});

/** GET /metrics — Prometheus scrape endpoint */
app.get('/metrics', async (_req, res) => {
  try {
    const metrics = await register.metrics();
    res.setHeader('Content-Type', register.contentType);
    res.send(metrics);
  } catch (err) {
    res.status(500).send('Error collecting metrics');
  }
});

// ─────────────────────────────────────────────────────────────
// Graceful shutdown
// ─────────────────────────────────────────────────────────────
let server;

function shutdown(signal) {
  log.error(`Received ${signal}, shutting down gracefully…`);
  server.close(() => {
    redis.quit().finally(() => process.exit(0));
  });
  // Force exit after 10 seconds
  setTimeout(() => process.exit(1), 10_000).unref();
}

server = app.listen(PORT, () => {
  log.info(`QRForge listening on port ${PORT}, hostname=${HOSTNAME}`);
});

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT',  () => shutdown('SIGINT'));

module.exports = app; // for testing
