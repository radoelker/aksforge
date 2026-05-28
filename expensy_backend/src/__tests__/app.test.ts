/**
 * Backend smoke tests.
 * All external connections are mocked before app is imported.
 */

// Must mock before any imports that trigger module loading
jest.mock('../config/db.config', () => jest.fn().mockResolvedValue(undefined));

jest.mock('../config/redis', () => ({
  __esModule: true,
  default: {
    get: jest.fn().mockResolvedValue(null),
    set: jest.fn().mockResolvedValue('OK'),
    del: jest.fn().mockResolvedValue(1),
  },
}));

// Mock Mongoose model to prevent buffering timeout
jest.mock('../models/expense.model', () => ({
  __esModule: true,
  default: {
    find: jest.fn().mockRejectedValue(new Error('DB not connected')),
    create: jest.fn().mockRejectedValue(new Error('DB not connected')),
  },
}));

import request from 'supertest';
import app from '../app';

afterAll(async () => {
  // Allow Jest to exit cleanly — no open handles
  await new Promise(resolve => setTimeout(resolve, 100));
});

describe('GET /metrics', () => {
  it('returns 200 with Prometheus content-type', async () => {
    const res = await request(app).get('/metrics');
    expect(res.status).toBe(200);
    expect(res.headers['content-type']).toMatch(/text\/plain/);
  });

  it('response body contains http_requests_total metric', async () => {
    const res = await request(app).get('/metrics');
    expect(res.text).toContain('http_requests_total');
  });
});

describe('GET /api/expenses — mocked DB error path', () => {
  it('returns 500 when model throws', async () => {
    const res = await request(app).get('/api/expenses');
    expect(res.status).toBe(500);
  }, 10000);
});