"use client";

import { useEffect, useState } from "react";
import type { Unlock } from "@/app/api/unlocks/route";

type Watch = { enabled: boolean; mode?: "upcoming" | "recent"; items: Unlock[]; error?: string };

const usdShort = (v: number) => (v >= 1e9 ? `$${(v / 1e9).toFixed(2)}B` : v >= 1e6 ? `$${(v / 1e6).toFixed(1)}M` : `$${Math.round(v).toLocaleString()}`);
const day = (d: string) => new Date(d).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" });

/** Token unlocks from Tokenomist: supply shocks that move prices, so every pool holding the token takes an LP loss. */
export function UnlockWatch() {
  const [w, setW] = useState<Watch | null>(null);
  useEffect(() => {
    fetch("/api/unlocks").then((r) => r.json()).then(setW).catch(() => setW({ enabled: true, items: [], error: "could not load unlocks" }));
  }, []);
  if (w && !w.enabled) return null; // no TOKENOMIST_API_KEY on this deployment

  return (
    <div className="pnl">
      <div className="pnl-head">
        <span className="pnl-title"><span className="n">//</span>Unlock watch</span>
        <span className="pill">via Tokenomist</span>
      </div>
      {!w && <div className="empty">loading unlocks…</div>}
      {w?.error && <div className="empty">{w.error}</div>}
      {w && !w.error && w.items.length === 0 && <div className="empty">No cliff unlocks in the window.</div>}
      {w && w.items.length > 0 && (
        <table className="dtable">
          <thead>
            <tr><th>Token</th><th>{w.mode === "recent" ? "Unlocked" : "Unlocks"}</th><th className="num">Value</th><th className="num">% of mcap</th><th>Mostly to</th></tr>
          </thead>
          <tbody>
            {w.items.map((u) => (
              <tr key={`${u.slug}-${u.date}`}>
                <td><b>{u.symbol}</b></td>
                <td>{day(u.date)}</td>
                <td className="num">{usdShort(u.valueUsd)}</td>
                <td className="num">{u.pctOfMcap >= 1 ? <span className="pill bad">{u.pctOfMcap.toFixed(2)}%</span> : `${u.pctOfMcap.toFixed(2)}%`}</td>
                <td className="dim">{u.topAllocation || "—"}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <div className="pnl-body"><div className="pnl-note">
        A large unlock hands new supply to investors and teams at once, and the price often moves on it. Every pool that
        holds the token takes an LP loss when it does: a 20% drop costs a 50/50 position 0.62%. Cover the position
        before the date, and CoverHook measures the loss and pays it out.
      </div></div>
    </div>
  );
}
