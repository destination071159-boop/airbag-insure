#!/usr/bin/env node
// Airbag keeper — makes the airbag deploy itself.
//
// Every few seconds it:
//   • records each market's trigger with CoverApp.poke(hash) when it changes, so an event is paid
//     even if the price recovers before a payout is fired, or the policy expires first;
//   • fires CoverApp.payout(id) when a policy has something due (depeg, LP loss, stock gap), and
//     again if a proportional loss deepens — the USDG lands in the note holder's wallet without
//     them doing anything; expired policies are still paid in the claim grace period;
//   • settles lapsed policies with CoverApp.expire(id) so underwriter capacity is recycled.
// All calls are permissionless: anyone can run this bot.
//
//   node scripts/keeper.mjs                      # local anvil (uses anvil dev account #2)
//   NETWORK=sepolia RPC_URL=… KEEPER_KEY=0x… DEMO_FEED=1 node scripts/keeper.mjs
//   DEMO_FEED=1 …                                # also re-post the demo oracles' last price when stale
import { readFileSync } from "node:fs";
import { createPublicClient, createWalletClient, http, parseAbi, formatUnits } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// NETWORK=local (default) | sepolia
const NETWORK = process.env.NETWORK ?? process.argv[2] ?? "local"; // or: node scripts/keeper.mjs sepolia
const dep = JSON.parse(readFileSync(new URL(`../src/lib/deployment.${NETWORK === "sepolia" ? 421614 : 31337}.json`, import.meta.url)));
const local = dep.chainId === 31337;
const rpc = process.env.RPC_URL ?? (local ? "http://127.0.0.1:8545" : "https://sepolia-rollup.arbitrum.io/rpc");
// anvil dev account #2 — a public test key, only ever used against the local chain
const key = process.env.KEEPER_KEY ?? (local ? "0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a" : null);
if (!key) throw new Error("set KEEPER_KEY for non-local chains");
const demoFeed = local || process.env.DEMO_FEED === "1";
const INTERVAL = Number(process.env.INTERVAL_MS ?? 3000);

const chain = { id: dep.chainId, name: local ? "anvil" : "arbitrum-sepolia", nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 }, rpcUrls: { default: { http: [rpc] } } };
const account = privateKeyToAccount(key);
const pub = createPublicClient({ chain, transport: http(rpc, { batch: true }) });
const wallet = createWalletClient({ chain, transport: http(rpc), account });

const app = parseAbi([
  "function nextPolicyId() view returns (uint256)",
  "function policies(uint256) view returns (bytes32 marketHash, uint256 coverNotional, uint64 expiry, bool claimed, address buyer, uint64 boughtAt, uint256 premium, uint256 paidOut)",
  "function payout(uint256 policyId) returns (uint256)",
  "function expire(uint256 policyId)",
  "function marketCount() view returns (uint256)",
  "function marketList(uint256) view returns (bytes32)",
  "function marketTrigger(bytes32) view returns (bool hit, uint256 payoutBps)",
  "function openEpisode(bytes32) view returns (uint64 start, uint64 lastSeen, uint16 maxBps)",
  "function poke(bytes32 strategyHash)",
]);
const POKE_EVERY = 60n; // while an event lasts, re-record it at most once a minute
const noteAbi = parseAbi(["function holderOf(uint256) view returns (address)"]);
const oracleAbi = parseAbi(["function latestPrice() view returns (uint256, uint256)", "function set(uint256)"]);

const t = () => new Date().toLocaleTimeString("en-GB");
const log = (...a) => console.log(`[${t()}]`, ...a);
const usd = (x) => Number(formatUnits(x, 18)).toLocaleString("en-US", { maximumFractionDigits: 2 });

const open = new Set(); // policy ids not yet settled
let seen = 0n; // policies discovered so far (ids are sequential — no log scans needed)

async function send(fn, args) {
  const { request, result } = await pub.simulateContract({ address: dep.coverApp, abi: app, functionName: fn, args, account });
  const hash = await wallet.writeContract(request);
  await pub.waitForTransactionReceipt({ hash });
  return { hash, result };
}

async function tick() {
  const next = await pub.readContract({ address: dep.coverApp, abi: app, functionName: "nextPolicyId" });
  for (; seen < next; seen++) open.add(seen);
  const now = (await pub.getBlock()).timestamp;

  if (demoFeed) {
    // demo oracles only move when someone posts; keep the last price fresh like a live feed would
    for (const o of [dep.oracle, dep.stockOracle].filter(Boolean)) {
      const [price, updatedAt] = await pub.readContract({ address: o, abi: oracleAbi, functionName: "latestPrice" });
      if (now - updatedAt > 3600n) {
        const hash = await wallet.writeContract({ address: o, abi: oracleAbi, functionName: "set", args: [price], chain });
        await pub.waitForTransactionReceipt({ hash });
        log(`feed heartbeat ${o.slice(0, 8)}… @ ${Number(price) / 1e8}`);
      }
    }
  }

  // record each market's trigger when it starts, deepens, ends, or once a minute while it lasts
  try {
    const count = await pub.readContract({ address: dep.coverApp, abi: app, functionName: "marketCount" });
    for (let i = 0n; i < count; i++) {
      const hash = await pub.readContract({ address: dep.coverApp, abi: app, functionName: "marketList", args: [i] });
      const [hit, bps] = await pub.readContract({ address: dep.coverApp, abi: app, functionName: "marketTrigger", args: [hash] });
      const [start, lastSeen, maxBps] = await pub.readContract({ address: dep.coverApp, abi: app, functionName: "openEpisode", args: [hash] });
      const due = hit ? start === 0n || bps > BigInt(maxBps) || now - lastSeen >= POKE_EVERY : start !== 0n;
      if (!due) continue;
      try {
        const { hash: tx } = await send("poke", [hash]);
        log(`${hit ? "📍 event recorded" : "✓ event ended"} on market ${hash.slice(0, 10)}…${hit ? ` (${Number(bps) / 100}%)` : ""}  ${tx.slice(0, 10)}`);
      } catch {
        // stale price — try again next round
      }
    }
  } catch {
    // a CoverApp from before events were recorded: nothing to poke
  }

  for (const id of [...open]) {
    const [, notional, expiry, claimed, , , , paidOut] = await pub.readContract({ address: dep.coverApp, abi: app, functionName: "policies", args: [id] });
    if (claimed) { open.delete(id); continue; }
    // pay what is due first (also inside the grace period after expiry), then release lapsed cover
    try {
      const holder = await pub.readContract({ address: dep.coverNote, abi: noteAbi, functionName: "holderOf", args: [id] });
      const { hash, result } = await send("payout", [id]);
      log(`🎈 AIRBAG DEPLOYED — policy #${id} paid ${usd(result)} USDG → ${holder}  ${hash.slice(0, 10)}`);
      continue; // a partial payout keeps the policy open; it leaves the set once it reads as claimed
    } catch {
      // nothing due (or price stale)
    }
    if (now > expiry) {
      try {
        const { hash } = await send("expire", [id]);
        log(`⌛ policy #${id} lapsed → capacity released (${usd(notional - paidOut)} USDG)  ${hash.slice(0, 10)}`);
        open.delete(id);
      } catch {
        // an event was recorded in its term: held until the claim grace period ends
      }
    }
  }
}

log(`keeper ${account.address} watching CoverApp ${dep.coverApp} on ${chain.name} (every ${INTERVAL / 1000}s)`);
for (;;) {
  try { await tick(); } catch (e) { log("round failed:", e.shortMessage ?? e.message); }
  await new Promise((r) => setTimeout(r, INTERVAL));
}
