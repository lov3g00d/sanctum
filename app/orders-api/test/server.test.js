import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { createApp, setDependencyReady } from '../src/server.js';

const server = createServer(createApp());
await new Promise((resolve) => server.listen(0, resolve));
const base = `http://127.0.0.1:${server.address().port}`;

after(() => server.close());

test('healthz is 200', async () => {
  const res = await fetch(`${base}/healthz`);
  assert.equal(res.status, 200);
});

test('readyz reflects dependency state', async () => {
  setDependencyReady(true);
  assert.equal((await fetch(`${base}/readyz`)).status, 200);
  setDependencyReady(false);
  assert.equal((await fetch(`${base}/readyz`)).status, 503);
  setDependencyReady(true);
});

test('metrics exposes prometheus text', async () => {
  const res = await fetch(`${base}/metrics`);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /http_requests_total/);
});

test('orders can be created and listed', async () => {
  const created = await fetch(`${base}/v1/orders`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ sku: 'WIDGET-1', quantity: 3 }),
  });
  assert.equal(created.status, 201);
  const order = await created.json();
  assert.equal(order.sku, 'WIDGET-1');

  const list = await (await fetch(`${base}/v1/orders`)).json();
  assert.ok(list.orders.some((o) => o.id === order.id));
});

test('invalid order is rejected', async () => {
  const res = await fetch(`${base}/v1/orders`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ sku: 'X' }),
  });
  assert.equal(res.status, 400);
});
