/**
 * RockAuto Demo Application
 *
 * A minimal Node.js server that demonstrates the full platform integration:
 * - Health endpoints (/healthz, /ready) for Kubernetes probes
 * - Metrics endpoint (/metrics) for Prometheus scraping
 * - Structured JSON logging for Fluent Bit → CloudWatch
 * - Environment variable config (injected by External Secrets Operator)
 *
 * This app doesn't do anything complex — its purpose is to prove the
 * platform works end-to-end: GitOps deploy, mTLS, monitoring, logging.
 */

const http = require('http');

const PORT = process.env.PORT || 8080;
const APP_NAME = process.env.APP_NAME || 'rockauto-demo-app';
const ENVIRONMENT = process.env.ENVIRONMENT || 'unknown';

// Simple in-memory metrics
let requestCount = 0;
let errorCount = 0;
const startTime = Date.now();

// Structured JSON logger (for CloudWatch Insights queries)
function log(level, message, extra = {}) {
  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level,
    app: APP_NAME,
    environment: ENVIRONMENT,
    message,
    ...extra
  }));
}

// Request handler
const server = http.createServer((req, res) => {
  requestCount++;

  // Health check — "is the app alive?"
  if (req.url === '/healthz') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', uptime: Math.floor((Date.now() - startTime) / 1000) }));
    return;
  }

  // Readiness check — "is the app ready to receive traffic?"
  if (req.url === '/ready') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ready' }));
    return;
  }

  // Prometheus metrics endpoint
  if (req.url === '/metrics') {
    const uptime = (Date.now() - startTime) / 1000;
    const metrics = [
      `# HELP http_requests_total Total HTTP requests`,
      `# TYPE http_requests_total counter`,
      `http_requests_total{app="${APP_NAME}"} ${requestCount}`,
      `# HELP http_errors_total Total HTTP errors`,
      `# TYPE http_errors_total counter`,
      `http_errors_total{app="${APP_NAME}"} ${errorCount}`,
      `# HELP app_uptime_seconds Application uptime in seconds`,
      `# TYPE app_uptime_seconds gauge`,
      `app_uptime_seconds{app="${APP_NAME}"} ${uptime}`,
    ].join('\n');

    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end(metrics + '\n');
    return;
  }

  // Main endpoint
  if (req.url === '/' || req.url === '/api') {
    log('info', 'Request received', { path: req.url, method: req.method });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      app: APP_NAME,
      environment: ENVIRONMENT,
      version: '1.0.0',
      message: 'RockAuto Cloud & Edge Platform — Demo Application',
      platform: {
        runtime: 'EKS (Kubernetes)',
        mesh: 'Istio (mTLS enabled)',
        gitops: 'ArgoCD',
        monitoring: 'Prometheus + Grafana',
        logging: 'Fluent Bit → CloudWatch',
        secrets: 'External Secrets Operator → AWS Secrets Manager',
        policies: 'Kyverno (admission control)'
      }
    }));
    return;
  }

  // 404 for everything else
  errorCount++;
  log('warn', 'Not found', { path: req.url });
  res.writeHead(404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ error: 'Not Found', path: req.url }));
});

server.listen(PORT, '0.0.0.0', () => {
  log('info', `${APP_NAME} started`, { port: PORT, environment: ENVIRONMENT });
});
