// Backend unit tests. They do not need MongoDB: only routes that never touch the database are exercised.
// Run with: npm test   (Node >= 18.1, uses the built-in test runner and global fetch)
process.env.MONGODB_URI = 'mongodb://127.0.0.1:1/shopnow-test?serverSelectionTimeoutMS=500';

const test = require('node:test');
const assert = require('node:assert');
const mongoose = require('mongoose');
const app = require('../server');

let server;
let base;

test.before(async () => {
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  base = `http://127.0.0.1:${server.address().port}`;
});

test.after(async () => {
  await new Promise((resolve) => server.close(resolve));
  await mongoose.disconnect();
});

test('GET / returns status OK', async () => {
  const res = await fetch(`${base}/`);
  assert.strictEqual(res.status, 200);
  const body = await res.json();
  assert.strictEqual(body.status, 'OK');
});

test('GET /api/health returns running message', async () => {
  const res = await fetch(`${base}/api/health`);
  assert.strictEqual(res.status, 200);
  const body = await res.json();
  assert.strictEqual(body.status, 'OK');
  assert.match(body.message, /ShopNow API/);
});

test('GET /metrics exposes Prometheus metrics', async () => {
  await fetch(`${base}/api/health`); // generate at least one sample
  const res = await fetch(`${base}/metrics`);
  assert.strictEqual(res.status, 200);
  const text = await res.text();
  assert.ok(text.includes('http_requests_total'));
  assert.ok(text.includes('http_request_duration_seconds'));
  assert.ok(text.includes('process_cpu_user_seconds_total'));
});

test('unknown route returns 404 JSON', async () => {
  const res = await fetch(`${base}/does-not-exist`);
  assert.strictEqual(res.status, 404);
  const body = await res.json();
  assert.strictEqual(body.error, 'Route not found');
});

test('POST /api/invoices validates required fields', async () => {
  const res = await fetch(`${base}/api/invoices`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ customerDetails: { name: '', phone: '' }, items: [], total: 0 }),
  });
  assert.strictEqual(res.status, 400);
  const body = await res.json();
  assert.match(body.error, /Missing required fields/);
});
