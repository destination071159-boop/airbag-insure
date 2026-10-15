import TileBackground from "@/components/TileBackground";
import SectionNav from "@/components/SectionNav";
import Navbar from "@/components/Navbar";
import AirbagDemo from "@/components/AirbagDemo";

/* ---------- content ---------- */

const STEPS = [
  {
    no: "01",
    title: "Underwriter ships a reserve. It never leaves their wallet.",
    body: (
      <>
        An underwriter commits USDG to a cover market through 1inch Aqua. Aqua records a{" "}
        <b>virtual balance</b> — the tokens stay in the underwriter&apos;s own wallet, free to sit in
        a vault and earn yield. No pool, no custody, no TVL honeypot.
      </>
    ),
    mech: (
      <>
        <em>aqua.ship()</em> → <em>CoverApp.registerMarket()</em> · reserve authenticated on-chain
      </>
    ),
  },
  {
    no: "02",
    title: "Buyers pay a risk-curve premium. They get a note.",
    body: (
      <>
        Premium is priced on a <b>utilization curve</b> — the fuller the book, the pricier the cover.
        It&apos;s pushed straight into the underwriter&apos;s reserve, and the buyer receives an
        ERC-6909 <b>CoverNote</b>: transferable, so cover can be sold or assigned.
      </>
    ),
    mech: (
      <>
        <em>quotePremium()</em> → <em>buyPolicy()</em> → aqua.push(premium) · note minted
      </>
    ),
  },
  {
    no: "03",
    title: "The pool moves. The airbag deploys — by itself.",
    body: (
      <>
        A Uniswap v4 <b>hook</b> measures the LP&apos;s impermanent loss from the pool&apos;s own prices. Past the
        deductible, a permissionless <b>keeper</b> calls <b>payout</b> and the money lands in whoever holds the
        note — pulled straight from the underwriter&apos;s reserve in one transaction. No claim form, no
        committee, no waiting period. If the loss deepens later, the difference is paid too.
      </>
    ),
    mech: (
      <>
        CoverHook loss → keeper <em>payout()</em> → <em>aqua.pull()</em> → note holder
      </>
    ),
  },
  {
    no: "04",
    title: "Nothing happens. The underwriter keeps the premium.",
    body: (
      <>
        Policies that lapse are settled by anyone — a keeper, the underwriter — which{" "}
        <b>frees the capacity</b> for the next buyer. The underwriter&apos;s P&amp;L is simply premiums
        earned minus payouts made, and it&apos;s verifiable on-chain at every block.
      </>
    ),
    mech: (
      <>
        <em>expire()</em> → capacity recycled · <em>aqua.dock()</em> to close the market
      </>
    ),
  },
];

const PRODUCTS = [
  { k: "live · 01", t: "Uniswap v4 LP-loss cover", p: "CoverHook measures an LP's real impermanent loss on a v4 pool; ILTrigger pays it out with a deductible, a cap, and a same-block manipulation guard." },
  { k: "live · 02", t: "Stablecoin depeg cover", p: "Oracle band trigger (Chainlink / Pyth adapters with staleness checks). Pays 100% of notional — pushed automatically." },
  { k: "live · 03", t: "Tokenized-stock gap cover", p: "Proportional payout when a tokenized stock gaps down — pays by how far it fell below the strike, not all-or-nothing." },
  { k: "reserve", t: "Tranched reserve", p: "Junior first-loss / senior-protected waterfall. Two risk appetites, one reserve." },
  { k: "reserve", t: "Yield reserve", p: "The reserve earns savings-vault yield while it backs cover, withdrawn just-in-time only when a payout fires. Underwriters stack premium + vault APY." },
  { k: "live · marketplace", t: "Underwriters compete", p: "Every underwriter publishes their own risk curve; the CoverRouter splits each order across the cheapest ones in one atomic transaction." },
];

const STACK = [
  { k: "loss oracle", v: "Uniswap v4", p: "A hook on the pool records each LP's entry and exit, so the loss is measured by the pool itself." },
  { k: "reserve rail", v: "1inch Aqua", p: "Shared-liquidity virtual balances: capital stays in the maker's wallet." },
  { k: "settlement", v: "USDG", p: "Paxos-issued, regulated stablecoin — premiums and payouts in the demo are in USDG." },
  { k: "chain", v: "Arbitrum", p: "Cheap enough to make per-policy notes and permissionless expiry practical." },
];

export default function Home() {
  return (
    <>
      <TileBackground still />
      <Navbar />
      <SectionNav />

      <header className="hero" id="top">
        <div className="hero-scrim" aria-hidden />
        <div className="container hero-grid">
          <div className="hero-text">
            <span className="hero-tag">Parametric LP cover · Uniswap v4 · 1inch Aqua · Arbitrum</span>
            <h1>
              LP cover
              <br />
              that deploys
              <br />
              itself<span className="dot">.</span>
            </h1>
            <p className="lede">
              Airbag is <b>parametric, provably-solvent cover</b> for Uniswap v4 liquidity providers. A
              v4 hook measures your <b>impermanent loss</b> on-chain; underwriters back the cover from their
              own wallets through <b>1inch Aqua</b>. When the loss passes 0.5%, the payout fires{" "}
              <span className="u">automatically</span> — <b>no claims desk, no custody</b>.
            </p>
            <div className="cta-row">
              <a className="btn btn-primary" href="/app">Open console →</a>
              <a className="btn btn-ghost" href="#how">How it works ↓</a>
              <a className="btn btn-ghost" href="/integrate">Integrate ↗</a>
            </div>
            <div className="hero-foot">
              <span>non-custodial</span>
              <span className="sep">/</span>
              <span>auto-payout</span>
              <span className="sep">/</span>
              <span>solvency on-chain</span>
              <span className="sep">/</span>
              <span>transferable cover</span>
            </div>
          </div>
          <div className="hero-visual">
            <AirbagDemo />
          </div>
        </div>
      </header>

      <section className="section" id="why">
        <div className="container">
          <div className="panel">
            <span className="kicker">// why now</span>
            <h2 className="sec-title">0x00 LPs earn fees, then lose more than they earned.</h2>
            <p className="sec-intro">
              Liquidity providers make DEXs work. When the two tokens in a pool move apart, an LP ends up worse off than if they had
              just held the tokens — <b>impermanent loss</b>. It often eats more than the fees, and there is nothing to insure it with:
              on-chain cover barely exists, and what does exist pays out after committee votes and waiting periods.
            </p>
            <div className="why">
              <div className="why-tile">
                <div className="why-v red">49.5%</div>
                <div className="why-k">of Uniswap v3 LPs lost money</div>
                <p>Half of liquidity providers did worse than simply holding the two tokens (pools over $10M, May–Sep 2021).</p>
                <a href="https://arxiv.org/abs/2111.09192" target="_blank" rel="noreferrer">Loesch et al. ↗</a>
              </div>
              <div className="why-tile">
                <div className="why-v red">$260M</div>
                <div className="why-k">lost vs $199M earned</div>
                <p>In the same study, impermanent loss was bigger than all the fees the LPs collected.</p>
                <a href="https://arxiv.org/abs/2111.09192" target="_blank" rel="noreferrer">arXiv 2111.09192 ↗</a>
              </div>
              <div className="why-tile">
                <div className="why-v">&lt; 2%</div>
                <div className="why-k">of DeFi TVL is insured</div>
                <p>On-chain insurance capital is in the hundreds of millions against ~$100B of TVL — over 98% of deposits are naked.</p>
                <a href="https://bex.co/blog/2026/05/03/defi-insurance-450m-q1-hacks-coverage-gap" target="_blank" rel="noreferrer">bex.co ↗</a>
              </div>
              <div className="why-tile">
                <div className="why-v green">1 tx</div>
                <div className="why-k">Airbag payout time</div>
                <p>Parametric trigger + keeper: once the hook sees the loss, one keeper transaction pays the holder. No claim at all.</p>
                <a href="/app">try it ↗</a>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="how">
        <div className="container">
          <div className="panel">
            <span className="kicker">// lifecycle</span>
            <h2 className="sec-title">0x01 From reserve to payout. Four calls.</h2>
            <p className="sec-intro">
              The whole protocol, start to finish — covered end-to-end by the <b>Lifecycle</b> test suite
              against the real Aqua contract.
            </p>
            <div className="steps">
              {STEPS.map((s) => (
                <div className="step" key={s.no}>
                  <div className="step-no">{s.no}</div>
                  <div>
                    <h3>{s.title}</h3>
                    <p>{s.body}</p>
                  </div>
                  <div className="mech">{s.mech}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="solvency">
        <div className="container">
          <div className="panel">
            <span className="kicker">// solvency</span>
            <h2 className="sec-title">0x02 It can&apos;t sell cover it can&apos;t pay.</h2>
            <p className="sec-intro">
              Every market enforces a <b>solvency floor</b>: outstanding cover can never exceed a fixed
              share of the reserve. Try to oversell and the transaction reverts. Anyone can read{" "}
              <b>solvency()</b> and check the backing at any block.
            </p>
            <div className="meter-wrap">
              <div className="meter">
                <div className="pnl-title">example market</div>
                <div className="meter-bar">
                  <div className="meter-fill" style={{ width: "58%" }} />
                  <div className="meter-floor" style={{ left: "80%" }}>
                    <span>floor 80%</span>
                  </div>
                </div>
                <div className="meter-legend">
                  <span>covered 580k</span>
                  <span>backing 1.0M USDG</span>
                </div>
              </div>
              <div className="meter eq">
                <div>
                  backing <b>= reserve + premiums − payouts</b>
                </div>
                <div>
                  outstanding <b>≤ backing × maxUtil</b>
                </div>
                <div>
                  aqua balance <b>== underwriter wallet</b> <span className="ok">✓ asserted in tests</span>
                </div>
                <div>
                  invariant fuzz <b>8,192 random buys × 128 runs</b> <span className="ok">✓ never over capacity</span>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="products">
        <div className="container">
          <div className="panel">
            <span className="kicker">// products</span>
            <h2 className="sec-title">0x03 One engine. Pluggable cover.</h2>
            <p className="sec-intro">
              The core <b>CoverApp</b> handles reserves, pricing, notes and payouts. What counts as an
              &quot;event&quot; is a plug-in: the Uniswap v4 LP-loss trigger, the built-in depeg band, or any contract implementing{" "}
              <b>ITrigger</b>.
            </p>
            <div className="cards">
              {PRODUCTS.map((c) => (
                <div className="card" key={c.t}>
                  <div className="card-k">{c.k}</div>
                  <h3>{c.t}</h3>
                  <p>{c.p}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="section" id="stack">
        <div className="container">
          <div className="panel">
            <span className="kicker">// stack</span>
            <h2 className="sec-title">0x04 Built on rails that already exist.</h2>
            <p className="sec-intro">No new token, no new pool. Airbag composes infrastructure that&apos;s already live.</p>
            <div className="stack">
              {STACK.map((s) => (
                <div key={s.v}>
                  <div className="k">{s.k}</div>
                  <div className="v">{s.v}</div>
                  <p>{s.p}</p>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      <section className="section final" id="final">
        <div className="container">
          <div className="panel">
            <h2>
              Buckle up.
              <br />
              <span className="red">Pools move.</span>
            </h2>
            <p>Become an LP, buy cover on your position, crash the pool, and watch the airbag deploy. Stablecoin depeg and stock cover run on the same engine.</p>
            <div className="cta-row">
              <a className="btn btn-primary" href="/app">Open console →</a>
            </div>
          </div>
        </div>
      </section>

      <footer className="footer">
        <div className="container footer-inner">
          <span>Airbag — Arbitrum Open House 2026</span>
          <span>non-custodial · parametric · provably solvent</span>
        </div>
      </footer>
    </>
  );
}
