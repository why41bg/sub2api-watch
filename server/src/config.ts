function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Missing environment variable: ${name}`);
  return value;
}

export const config = {
  adminKey: required('SUB2API_ADMIN_API_KEY'),
  watchKey: required('WATCH_API_KEY'),
  baseUrl: (process.env.SUB2API_BASE_URL || 'http://127.0.0.1:8080').replace(/\/+$/, ''),
  timezone: process.env.SUB2API_TIMEZONE || 'Asia/Shanghai',
  host: process.env.HOST || '127.0.0.1',
  port: Number(process.env.PORT || 8787),
};

const upstream = new URL(config.baseUrl);
if (!['http:', 'https:'].includes(upstream.protocol) || upstream.username || upstream.password || upstream.search || upstream.hash) {
  throw new Error('SUB2API_BASE_URL must be an HTTP(S) URL without credentials, query or fragment');
}
if (!Number.isInteger(config.port) || config.port < 1 || config.port > 65535) {
  throw new Error('PORT must be an integer from 1 to 65535');
}
if (config.watchKey === config.adminKey) throw new Error('WATCH_API_KEY must differ from the admin API key');

export const dateFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: config.timezone, year: 'numeric', month: '2-digit', day: '2-digit',
});
