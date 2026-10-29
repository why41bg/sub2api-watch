import { config, dateFormatter } from './config.js';

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

type Params = Record<string, string | number>;
type User = { id: number; email: string };
type ApiKey = { id: number; name: string };
type Account = {
  id: number;
  name: string;
  status: string;
  extra?: Record<string, unknown>;
};
type WindowUsage = { utilization?: number; resets_at?: string; remaining_seconds?: number };
type AccountUsage = { updated_at?: string; five_hour?: WindowUsage; seven_day?: WindowUsage };
type Stats = {
  total_requests: number;
  total_tokens: number;
  total_input_tokens: number;
  total_output_tokens: number;
  total_cache_read_tokens: number;
  total_cache_creation_tokens: number;
};

async function get<T>(path: string, params: Params = {}): Promise<T> {
  const url = new URL(`${config.baseUrl}/api/v1${path}`);
  url.search = new URLSearchParams(Object.entries({ timezone: config.timezone, ...params })
    .map(([key, value]) => [key, String(value)])).toString();
  try {
    const response = await fetch(url, {
      headers: { 'x-api-key': config.adminKey },
      redirect: 'error',
      signal: AbortSignal.timeout(20000),
    });
    if (response.status === 404) throw new HttpError(404, 'Not found');
    if (!response.ok) throw new HttpError(502, 'Sub2api request failed');
    const body = await response.json() as { code: number; data: T };
    if (body.code !== 0 || body.data == null) throw new HttpError(502, 'Invalid sub2api response');
    return body.data;
  } catch (error) {
    if (error instanceof HttpError) throw error;
    if (error instanceof Error && error.name === 'TimeoutError') throw new HttpError(504, 'Sub2api request timed out');
    throw new HttpError(502, 'Sub2api is unavailable');
  }
}

async function list<T>(path: string, params: Params = {}): Promise<T[]> {
  const items: T[] = [];
  for (let page = 1; ; page++) {
    const data = await get<{ items: T[]; pages: number }>(path, { ...params, page, page_size: 100 });
    if (!Array.isArray(data.items) || !Number.isInteger(data.pages)) throw new HttpError(502, 'Invalid sub2api list');
    items.push(...data.items);
    if (page >= data.pages || !data.items.length) return items;
  }
}

export async function users() {
  return (await list<User>('/admin/users')).map(({ id, email }) => ({ id, email }));
}

export async function keys(userId: number) {
  return (await list<ApiKey>(`/admin/users/${userId}/api-keys`)).map(({ id, name }) => ({ id, name }));
}

function quota(used: unknown, reset: unknown, seconds?: unknown) {
  return {
    remainingPercent: typeof used === 'number' && Number.isFinite(used)
      ? Math.max(0, Math.min(100, 100 - used)) : null,
    resetsAt: typeof reset === 'string' && Date.parse(reset) > Date.now()
      && !(typeof seconds === 'number' && seconds <= 0) ? reset : null,
  };
}

async function accountQuota(account: Account) {
  const result = { id: account.id, name: account.name, status: account.status };
  try {
    const usage = await get<AccountUsage>(`/admin/accounts/${account.id}/usage`, { force: 'true' });
    return {
      ...result, stale: false, updatedAt: usage.updated_at ?? null,
      fiveHour: quota(usage.five_hour?.utilization, usage.five_hour?.resets_at, usage.five_hour?.remaining_seconds),
      sevenDay: quota(usage.seven_day?.utilization, usage.seven_day?.resets_at, usage.seven_day?.remaining_seconds),
    };
  } catch {
    const extra = account.extra ?? {};
    return {
      ...result, stale: true,
      updatedAt: typeof extra.codex_usage_updated_at === 'string' ? extra.codex_usage_updated_at : null,
      fiveHour: quota(extra.codex_5h_used_percent, extra.codex_5h_reset_at, extra.codex_5h_reset_after_seconds),
      sevenDay: quota(extra.codex_7d_used_percent, extra.codex_7d_reset_at, extra.codex_7d_reset_after_seconds),
    };
  }
}

export async function accounts() {
  const source = await list<Account>('/admin/accounts', { platform: 'openai' });
  const results: Awaited<ReturnType<typeof accountQuota>>[] = [];
  // Limit simultaneous upstream refreshes when the account pool grows.
  for (let index = 0; index < source.length; index += 4) {
    results.push(...await Promise.all(source.slice(index, index + 4).map(accountQuota)));
  }
  return results;
}

export async function todayUsage(userId?: number, apiKeyId?: number) {
  if (apiKeyId !== undefined) {
    if (userId === undefined) throw new HttpError(400, 'userId is required with apiKeyId');
    if (!(await keys(userId)).some(key => key.id === apiKeyId)) throw new HttpError(404, 'API key not found for this user');
  }
  const date = dateFormatter.format(new Date());
  const params: Params = { start_date: date, end_date: date, nocache: 1 };
  if (userId !== undefined) params.user_id = userId;
  if (apiKeyId !== undefined) params.api_key_id = apiKeyId;
  const stats = await get<Stats>('/admin/usage/stats', params);
  return {
    date, timezone: config.timezone, userId: userId ?? null, apiKeyId: apiKeyId ?? null,
    requests: stats.total_requests,
    tokens: {
      total: stats.total_tokens,
      input: stats.total_input_tokens,
      output: stats.total_output_tokens,
      cacheRead: stats.total_cache_read_tokens,
      cacheCreation: stats.total_cache_creation_tokens,
    },
    updatedAt: new Date().toISOString(),
  };
}
