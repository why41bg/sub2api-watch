import { timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { config } from './config.js';
import { accounts, HttpError, keys, todayUsage, users } from './sub2api.js';

const expectedAuth = Buffer.from(`Bearer ${config.watchKey}`);
function authorized(header = ''): boolean {
  const actual = Buffer.from(header);
  return actual.length === expectedAuth.length && timingSafeEqual(actual, expectedAuth);
}

function id(value: string | null): number | undefined {
  if (value === null) return undefined;
  if (!/^[1-9]\d*$/.test(value) || !Number.isSafeInteger(Number(value))) {
    throw new HttpError(400, 'IDs must be positive integers');
  }
  return Number(value);
}

const server = createServer(async (request, response) => {
  response.setHeader('Content-Type', 'application/json; charset=utf-8');
  response.setHeader('Cache-Control', 'no-store');
  try {
    if (request.method !== 'GET') {
      response.setHeader('Allow', 'GET');
      throw new HttpError(405, 'Method not allowed');
    }
    const url = new URL(request.url || '/', 'http://localhost');
    if (url.pathname === '/health') {
      response.end(JSON.stringify({ status: 'ok' }));
      return;
    }
    if (!authorized(request.headers.authorization)) {
      response.setHeader('WWW-Authenticate', 'Bearer');
      throw new HttpError(401, 'Unauthorized');
    }

    let data: unknown;
    const keyRoute = url.pathname.match(/^\/users\/([1-9]\d*)\/keys$/);
    if (url.pathname === '/users') {
      data = { users: await users() };
    } else if (keyRoute) {
      data = { keys: await keys(id(keyRoute[1])!) };
    } else if (url.pathname === '/accounts') {
      data = { accounts: await accounts(), fetchedAt: new Date().toISOString() };
    } else if (url.pathname === '/usage/today') {
      data = await todayUsage(id(url.searchParams.get('userId')), id(url.searchParams.get('apiKeyId')));
    } else {
      throw new HttpError(404, 'Not found');
    }
    response.end(JSON.stringify(data));
  } catch (error) {
    response.statusCode = error instanceof HttpError ? error.status : 500;
    response.end(JSON.stringify({ error: error instanceof HttpError ? error.message : 'Internal server error' }));
  }
});

server.listen(config.port, config.host, () => {
  console.log(`Sub2API Watch Bridge listening on ${config.host}:${config.port}`);
});
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => server.close());
}
