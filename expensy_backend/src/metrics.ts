import client from 'prom-client';
import { Request, Response, NextFunction } from 'express';

// ─────────────────────────────────────────
// Counters
// ─────────────────────────────────────────

// Total requests — unlabelled, lightweight overall count
export const totalHttpRequestsCounter = new client.Counter({
    name: 'http_requests_total_count',
    help: 'Total number of HTTP requests (unlabelled)',
});

// Per-request detail counter
export const httpRequestsCounter = new client.Counter({
    name: 'http_requests_total',
    help: 'Total number of HTTP requests with labels',
    labelNames: ['method', 'route', 'statusCode'],
});

// Error counter — 4xx and 5xx responses
export const httpErrorsCounter = new client.Counter({
    name: 'http_errors_total',
    help: 'Total number of HTTP error responses (4xx + 5xx)',
    labelNames: ['method', 'route', 'statusCode'],
});

// ─────────────────────────────────────────
// Histogram
// ─────────────────────────────────────────

// Request duration in seconds — buckets tuned for a typical API
export const httpRequestDurationHistogram = new client.Histogram({
    name: 'http_request_duration_seconds',
    help: 'HTTP request duration in seconds',
    labelNames: ['method', 'route', 'statusCode'],
    buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
});

// ─────────────────────────────────────────
// Middleware
// ─────────────────────────────────────────

export function httpMetricsMiddleware(req: Request, res: Response, next: NextFunction): void {
    const startTime = Date.now();

    res.on('finish', () => {
        const durationSeconds = (Date.now() - startTime) / 1000;
        const method = req.method;
        // req.route?.path gives the matched pattern (e.g. /api/items/:id)
        // rather than the full URL — avoids high-cardinality labels
        const route = (req.route?.path as string) || req.originalUrl || req.url;
        const statusCode = res.statusCode.toString();

        httpRequestsCounter.labels(method, route, statusCode).inc();
        totalHttpRequestsCounter.inc();
        httpRequestDurationHistogram.labels(method, route, statusCode).observe(durationSeconds);

        if (res.statusCode >= 500) {
            httpErrorsCounter.labels(method, route, statusCode).inc();
        }
    });

    next();
}