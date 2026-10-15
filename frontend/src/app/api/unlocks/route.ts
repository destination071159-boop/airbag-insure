// Token unlock radar, from the Tokenomist API (https://docs.tokenomist.ai). Large cliff unlocks add sell pressure,
// so the price moves and every pool holding the token takes an LP loss: the moment to buy LP cover. This runs on
// the server so TOKENOMIST_API_KEY never reaches the browser, and keeps each answer for an hour to save API credits.
export const runtime = 'nodejs';
export const dynamic = 'force-dynamic'; // read the key at request time, not at build time

const API = 'https://api.tokenomist.ai/v5';
// token slugs as Tokenomist lists them (GET /v5/token/list); unknown slugs are skipped
const WATCH = (process.env.TOKENOMIST_TOKENS || 'arbitrum,optimism,sui,aptos,starknet,celestia,zksync,ethena').split(',');
const DAY = 86_400_000;

type Allocation = { allocationName?: string; standardAllocationName?: string; cliffAmount?: number };
type Event = {
  unlockDate: string;
  tokenName: string;
  tokenSymbol: string;
  cliffUnlocks?: { cliffAmount?: number; cliffValue?: number; valueToMarketCap?: number; allocationBreakdown?: Allocation[] };
};
export type Unlock = { symbol: string; name: string; slug: string; date: string; amount: number; valueUsd: number; pctOfMcap: number; topAllocation: string };

const ymd = (t: number) => new Date(t).toISOString().slice(0, 10);

async function events(key: string, slug: string, start: string, end: string): Promise<Unlock[]> {
  const url = `${API}/unlock/events/${encodeURIComponent(slug)}?start=${start}&end=${end}&pageSize=50`;
  const r = await fetch(url, { headers: { 'x-api-key': key }, cache: 'no-store' });
  if (!r.ok) return [];
  const j = (await r.json()) as { data?: Event[] };
  return (j.data ?? [])
    .filter((e) => (e.cliffUnlocks?.cliffValue ?? 0) > 0)
    .map((e) => {
      const top = [...(e.cliffUnlocks?.allocationBreakdown ?? [])].sort((a, b) => (b.cliffAmount ?? 0) - (a.cliffAmount ?? 0))[0];
      return {
        symbol: e.tokenSymbol,
        name: e.tokenName,
        slug,
        date: e.unlockDate,
        amount: e.cliffUnlocks?.cliffAmount ?? 0,
        valueUsd: e.cliffUnlocks?.cliffValue ?? 0,
        pctOfMcap: e.cliffUnlocks?.valueToMarketCap ?? 0,
        topAllocation: top?.standardAllocationName || top?.allocationName || '',
      };
    });
}

let cached: { at: number; body: unknown } | null = null;

export async function GET() {
  const key = process.env.TOKENOMIST_API_KEY;
  if (!key) return Response.json({ enabled: false, items: [] });
  const now = Date.now();
  if (cached && now - cached.at < 3600_000) return Response.json(cached.body);
  try {
    // upcoming unlocks first; plans without forward data (e.g. the free trial) fall back to the last 90 days
    let mode: 'upcoming' | 'recent' = 'upcoming';
    let items = (await Promise.all(WATCH.map((s) => events(key, s.trim(), ymd(now), ymd(now + 60 * DAY))))).flat();
    if (items.length === 0) {
      mode = 'recent';
      items = (await Promise.all(WATCH.map((s) => events(key, s.trim(), ymd(now - 90 * DAY), ymd(now))))).flat();
    }
    items.sort((a, b) => (mode === 'upcoming' ? a.date.localeCompare(b.date) : b.date.localeCompare(a.date)));
    const body = { enabled: true, mode, items: items.slice(0, 8) };
    cached = { at: now, body };
    return Response.json(body);
  } catch {
    return Response.json({ enabled: true, mode: 'upcoming', items: [], error: 'Tokenomist is not reachable right now' });
  }
}
