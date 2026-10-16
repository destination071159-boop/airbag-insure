# Airbag

**LP cover that deploys itself.**

Airbag is parametric cover for **Uniswap v4 liquidity providers** on Arbitrum. An LP pays a small premium and
holds a transferable cover note linked to their position. When the pool moves and the LP loss passes 0.5%, a
**Uniswap v4 hook measures it on-chain**, a permissionless keeper fires the payout and **the USDG lands in the
holder's wallet automatically**, with no claim form, no committee and no waiting period. The same engine also
covers a **USDG depeg** and a **tokenized-stock gap-down**, and **Tokenomist** unlock data shows an LP when a
pool is about to move. Underwriters back the cover from their **own wallets through 1inch Aqua**, publish their
own risk curves, and compete on price.

**Live on Arbitrum Sepolia** · **13 contracts, all source-verified** · **62 Foundry tests passing** · three
live cover products · automatic payouts · 3 competing underwriters · a real Uniswap v4 pool + hook ·
token unlock watch from Tokenomist

## Demo Video

[![Airbag Demo](./media/demo-cover.png)](https://youtu.be/H3WE77UesJ8)

| | |
|---|---|
| 🌐 **Live app** | **[airbag-insure.vercel.app](https://airbag-insure.vercel.app)**: Arbitrum Sepolia, connect MetaMask (test USDG is free to mint) |
| 📜 **Contracts** | [Deployed addresses](#61-deployed-contracts-arbitrum-sepolia--chain-421614) (all verified on Arbiscan + Sourcify) · history in [`DEPLOYMENTS.md`](DEPLOYMENTS.md) |
| 🧩 **Integrate** | `/integrate` in the app: a drop-in "Protect this balance" widget and a one-call contract API |
| 🧪 **Try it yourself** | [Run it locally](#11-run-it-locally), or open the live app, connect MetaMask on Arbitrum Sepolia and mint test USDG |

---

## Contents

1. [The problem](#1-the-problem)
2. [The solution](#2-the-solution)
3. [How it works (worked example)](#3-how-it-works)
4. [What's live](#4-whats-live)
5. [Solvency model: what is guaranteed, what is not](#5-solvency-model)
6. [Architecture](#6-architecture) · [deployed contracts](#61-deployed-contracts-arbitrum-sepolia--chain-421614)
7. [Tech stack & integration status](#7-tech-stack--integration-status)
8. [Market fit](#8-market-fit)
9. [Roadmap & milestones](#9-roadmap--milestones)
10. [Judging criteria](#10-judging-criteria)
11. [Run it locally](#11-run-it-locally)
12. [Repository layout](#12-repository-layout)
13. [Security, limits & honest caveats](#13-security-limits--honest-caveats)
14. [Further reading](#14-further-reading)

---

## 1. The problem

**Liquidity providers lose money when prices move, and almost nobody can insure them.**

- **LPs lose more than they earn.** In a study of Uniswap v3, **49.5%** of liquidity providers did worse than if
  they had just held the two tokens: **$260M** lost to price moves (impermanent loss) against **$199M** earned in
  fees, May–Sep 2021 ([Loesch et al., Bancor & Topaze Blue](https://arxiv.org/abs/2111.09192)).
- **The moves have dates.** Token unlocks release new supply to teams and investors on a known schedule, and the
  price often moves on it. Every pool that holds the token takes the LP loss, yet there is no product an LP can
  buy before the date.
- **Pegs break too.** On 11 March 2023, USDC fell to about **$0.87** after Circle disclosed that $3.3B of its
  reserves were stuck at Silicon Valley Bank. It took about three days to recover
  ([CNBC](https://www.cnbc.com/2023/03/11/stablecoin-usdc-breaks-dollar-peg-after-firm-reveals-it-has-3point3-billion-in-svb-exposure.html)).
  A peg is only as strong as the bank the reserves sit in.
- **On-chain cover barely exists.** Less than 2% of DeFi's total value locked is insured, and insurance capital
  is in the hundreds of millions against roughly $100B of deposits
  ([bex.co](https://bex.co/blog/2026/05/03/defi-insurance-450m-q1-hacks-coverage-gap)).
- **Existing cover pays slowly and discretionarily.** Claims go through assessment votes, committees and waiting
  periods. When a peg breaks, holders need the money *now*, not after a governance process.
- **Regulated stablecoins are growing up.** Paxos's Global Dollar (**USDG**) is issued under Singapore's MAS
  framework and the EU's MiCA, which makes it the kind of dollar that payment apps, payroll tools and treasuries
  actually hold. Those users want protection they can explain to an auditor.

## 2. The solution

Airbag combines four ideas in one product:

| | What it does | Why it matters |
|---|---|---|
| **Parametric trigger** | Each product has an objective trigger: USDG ≤ $0.97, LP loss past 0.5%, or TSLAx below $250 | No claims process and no dispute: the oracle or the pool price decides |
| **Automatic payout** | A permissionless keeper calls `payout(policyId)` the moment the trigger fires, and the USDG goes to whoever holds the note | **The insured doesn't even have to be online.** This is the "airbag" |
| **Non-custodial reserve on 1inch Aqua** | Underwriters `ship` a USDG reserve to Aqua as a *virtual balance*. The tokens stay in their own wallet, or in a savings vault earning yield | No pooled honeypot. Capital can earn premiums **and** vault yield at the same time |
| **Competitive marketplace** | Every underwriter publishes a risk curve. A router splits each order across the cheapest curves atomically | Price discovery for risk, instead of an admin-set rate |

Around it: **ERC-6909 cover notes** make cover transferable (the holder is paid), a **solvency floor** stops
any market selling more cover than it can pay, and a **checkout widget** lets any app sell Airbag cover to its
own users.

## 3. How it works

### In pictures

**Uniswap v4 LP loss.** The buyer adds liquidity, pays a premium and gets a cover note. `CoverHook` measures the
position's impermanent loss on-chain; past 0.5%, Airbag orders `Aqua.pull` and the underwriter's money goes
straight to the buyer.

![Airbag LP cover concept](./media/airbag-lp-concept.png)

<details>
<summary>The contracts behind one LP payout</summary>

![Airbag LP cover architecture](./media/airbag-lp-full.png)

</details>

**Stablecoin depeg.** Same engine, built-in trigger: a fresh price at or below $0.97 pays 100% of the cover. With
several underwriters, the router splits the order across the cheapest curves in one transaction.

![Airbag depeg cover concept](./media/airbag-depeg.png)

<details>
<summary>The contracts behind one depeg payout</summary>

![Airbag depeg cover architecture](./media/airbag-depeg-full.png)

</details>

The diagrams show a USDC reserve, a market setting that pays out in a coin other than the one that broke. The
live demo markets are backed and paid in USDG. Sources: `pitch/diagrams/diagram.html` (re-render with
`node pitch/diagrams/render.mjs`, then copy the PNGs to `media/`).

### Worked example

**The buyer.** Alice holds 50,000 USDG in her wallet and wants 7 days of depeg cover. These are live quotes from
the Arbitrum Sepolia deployment for exactly that order:

| Underwriter | Risk curve (annual rate) | Quote for 50,000 USDG · 7 days |
|---|---|---:|
| Airbag Genesis (reserve in a savings vault) | 1% → 10% as the book fills | 36.54 USDG |
| Underwriter B | 0.6% → 14%, cheap until busy | **6.99 USDG** |
| Underwriter C | 1.5% → 6%, steady | 18.87 USDG |

The router sends Alice's order to the cheapest curve. She pays **6.99 USDG** (about 0.73% a year) and receives an
ERC-6909 cover note.

**The depeg.** USDG trades at $0.92, below the $0.97 trigger. Within one keeper round, the keeper calls
`payout()` and **50,000 USDG lands in Alice's wallet**. She sends no transaction and fills in no form. If she had
sold or gifted the note, the new holder would be paid instead.

**No depeg.** The policy expires, anyone settles it with `expire()`, and the capacity is freed for the next
buyer. The underwriter keeps the premium.

**The other two products** use the same engine with a different trigger:

| Product | Trigger | Example payout on 100,000 USDG of cover |
|---|---|---|
| **Uniswap v4 LP loss** (wstETH/WETH) | LP impermanent loss measured by `CoverHook` | 1.98% LP loss, 0.5% deductible, 5% cap → **32,880 USDG** |
| **Tokenized-stock gap-down** (TSLAx) | Oracle price below the $250 strike | TSLAx at $200 (−20%) → **20,000 USDG** |

**The underwriter.** An underwriter earns two streams on the same capital: **premiums** from every policy sold
against their curve, and **savings-vault yield** on the reserve (4.5% APR in the demo), which is withdrawn just
in time only when a payout fires. The console shows the book's expected APY, premiums, vault yield, payouts,
net P&L and loss ratio.

**Pricing honesty:** premiums are an **annual rate × term**, like real insurance. Rates rise with utilization
along the underwriter's curve, and each order is priced at its post-trade utilization, so the last buyer before
a market fills pays the most.

## 4. What's live

Everything below runs against the deployed contracts on Arbitrum Sepolia.

| Area | Features |
|---|---|
| **Buy cover** | Three products in one catalog · amount and term · live quote · the risk curve with "now" and "your rate" markers · the order book across underwriters, with your fill per underwriter · one-transaction routed buy · LP flow: "Become an LP" on the real v4 pool, then buy + link cover to the position |
| **Unlock watch** | On the LP-loss product: upcoming token unlocks from Tokenomist (date, value, % of market cap, who receives them). An unlock moves the price, and every pool holding the token takes the LP loss, so an LP can cover the position before the date |
| **Automatic payout** | Keeper bot (`frontend/scripts/keeper.mjs`) fires every triggered policy · the "Airbag deployed" banner when a payout lands in your wallet · a manual "Claim now" is still available |
| **Event simulator** | Move the USDG feed ("Depeg → $0.92") · move the TSLAx feed ("Earnings miss −20%") · a real swap through the v4 pool ("wstETH depeg −33%") |
| **Underwrite** | Your book: expected APY (premiums + vault), premiums, vault yield, payouts, net P&L, loss ratio · per-market table · open a new market: reserve, trigger band, solvency floor, and a **draggable risk-curve editor** with presets |
| **Keeper** | Every open policy with its status · run a keeper round from the browser (payout what's due, settle what lapsed) |
| **Integrate** | `/app/embed?amount=…&partner=…`: a "Protect your 25,000 USDG" widget any app can iframe · `/integrate`: live preview, the iframe snippet and the contract call |

Verified end to end: 62 Foundry tests (including a full lifecycle suite, an 8,192-call invariant fuzz and a
real v4 IL-cover suite), browser runs of every flow on a local chain and on Arbitrum Sepolia, and a keeper that
paid out depeg, LP-loss and stock-gap policies automatically.

## 5. Solvency model

What Airbag guarantees, and what it doesn't. We keep this honest.

| Property | How it's enforced | Guaranteed? |
|---|---|---|
| A market can't sell more cover than its floor allows | `outstanding ≤ backing × maxUtil`, checked on every buy (reverts otherwise); fuzzed with 8,192 random buys | ✅ on-chain |
| Payouts are paid from real reserves | `aqua.pull()` transfers from the underwriter's wallet in the same transaction, and reverts if unbacked | ✅ atomic |
| Solvency is publicly checkable | `solvency(market)` returns backing, cover in force and utilization at any block | ✅ anyone can read it |
| Cover can't be bought after the loss (LP product) | the policy is bound to the LP's position at a baseline price; the loss is measured from there | ✅ tested |
| Flash-loan price pushes can't fake an LP claim | `CoverHook` measures from the **block-open** price, not the live price | ✅ tested |
| The reserve can't be withdrawn while cover is outstanding | Aqua lets a maker `dock` (withdraw) at any time | ❌ **not enforced**, see §13 |
| One wallet can't back two markets with the same USDG | Aqua balances are virtual; only the optional `SolventBook` aggregate floor catches double counting | 🟡 optional |

## 6. Architecture

```mermaid
%%{init: {"flowchart": {"nodeSpacing": 40, "rankSpacing": 55}, "themeVariables": {"fontSize": "18px"}}}%%
flowchart TB
  B["Buyer / partner app<br/>console · widget"]
  K["Keeper bot<br/>permissionless"]

  subgraph SELL["1 · Sell: marketplace"]
    RT["CoverRouter<br/>cheapest curves first"]
    APP["CoverApp<br/>markets · premiums · payouts"]
    NOTE["CoverNote<br/>ERC-6909 policy"]
  end

  subgraph BACK["2 · Back: non-custodial reserves"]
    AQ["1inch Aqua<br/>virtual balances"]
    YR["YieldReserve<br/>+ savings vault"]
    UW["Underwriter wallets"]
  end

  subgraph TRIG["3 · Trigger: what pays"]
    OR[("Price oracles<br/>USDG · TSLAx")]
    ILT["ILTrigger"]
    GT["PriceGapTrigger"]
    HK["CoverHook<br/>Uniswap v4"]
  end

  B -->|buy| RT
  RT -->|legs| APP
  APP -->|mint| NOTE
  APP -->|premium push / payout pull| AQ
  AQ --> UW
  AQ --> YR
  K -->|"payout(id)"| APP
  APP -->|depeg band| OR
  APP -->|ITrigger| ILT
  APP -->|ITrigger| GT
  ILT -->|LP loss| HK
  GT --> OR
```

| Contract | Role |
|---|---|
| `CoverApp` | The core. Registers markets (an Aqua strategy each), prices premiums on the risk curve (annual rate × term), enforces the solvency floor, mints notes, and settles through `payout()` (anyone, pays the holder), `claim()` (the holder) or `expire()` (anyone, after expiry) |
| `CoverNote` | ERC-6909 policy notes: transferable, with `holderOf` so the keeper knows who to pay |
| `CoverRouter` | Marketplace executor: fills a solver-built route across many underwriters atomically, with a premium cap and refund |
| `RiskCurve` (library) | `rate(u) = start + (end − start) · u^k`, monotonic in utilization |
| `CoverHook` | Uniswap v4 hook: records each LP's entry and exit (the real LP via `IMsgSender`), full-range IL maths, block-open price guard, depeg flag |
| `ILTrigger` | Maps v4 LP loss to a payout: bind a policy to a live position, pay `(IL − deductible) / (cap − deductible)` |
| `PriceGapTrigger` | Pays the percentage an asset falls below a strike (tokenized stocks, RWAs) |
| `YieldReserve` | Underwriter account whose reserve sits in an ERC-4626 vault; withdraws just in time when a payout fires |
| `SolventBook` · `TranchedReserve` | Built and tested, not in the live flow: an attestor-fed aggregate solvency floor, and junior/senior reinsurance tranches |

### 6.1 Deployed contracts (Arbitrum Sepolia · chain 421614)

All 13 contracts are verified on **Arbiscan** and **Sourcify (exact match)**. Click an address to open it on Arbiscan.

| Contract | Role | Address |
|---|---|---|
| **CoverApp** | Core: markets, premiums, payouts | [`0xe7ed61808A361f60a767Bb2e4625D565E17fc9d9`](https://sepolia.arbiscan.io/address/0xe7ed61808A361f60a767Bb2e4625D565E17fc9d9) |
| **CoverRouter** | Marketplace: routed buys | [`0x11A85418636801774ACeFb7a9C67c70c3d4127F0`](https://sepolia.arbiscan.io/address/0x11A85418636801774ACeFb7a9C67c70c3d4127F0) |
| **CoverNote** | ERC-6909 cover notes | [`0xE04704211f2D3015031762F7d95e8ddC1d60a5e7`](https://sepolia.arbiscan.io/address/0xE04704211f2D3015031762F7d95e8ddC1d60a5e7) |
| **CoverHook** | Uniswap v4 hook (LP loss) | [`0x8d9FfDe2ABe7fB498Cf44692eD4DEF990D698Ac0`](https://sepolia.arbiscan.io/address/0x8d9FfDe2ABe7fB498Cf44692eD4DEF990D698Ac0) |
| **ILTrigger** | LP-loss payouts | [`0x1ceE0DbeA55eC5C545b243d6901de7197dD9Ce56`](https://sepolia.arbiscan.io/address/0x1ceE0DbeA55eC5C545b243d6901de7197dD9Ce56) |
| **PriceGapTrigger** | Stock gap-down payouts | [`0x480C8BA3f8BDCdc2d59F21dd9181CFF05b5C678B`](https://sepolia.arbiscan.io/address/0x480C8BA3f8BDCdc2d59F21dd9181CFF05b5C678B) |
| **Aqua** | 1inch Aqua, unmodified copy (see §7) | [`0x6Ec59Cf8522A0Ca19bca3097CB0fa8fE363231A6`](https://sepolia.arbiscan.io/address/0x6Ec59Cf8522A0Ca19bca3097CB0fa8fE363231A6) |
| **YieldReserve** | Genesis underwriter, reserve in a vault | [`0xe589036Cc53ad999edeB2455A4D7618Da7Ea081a`](https://sepolia.arbiscan.io/address/0xe589036Cc53ad999edeB2455A4D7618Da7Ea081a) |
| **DripVault** | Demo savings vault (4.5% APR) | [`0x31F77137213547BDB67937ab62d5FcA2561a87f0`](https://sepolia.arbiscan.io/address/0x31F77137213547BDB67937ab62d5FcA2561a87f0) |
| **USDG (test)** | Mintable test USDG | [`0x08Fa806EC09e631EF271E15bD025542Ef812e8a3`](https://sepolia.arbiscan.io/address/0x08Fa806EC09e631EF271E15bD025542Ef812e8a3) |
| **USDG/USD feed (demo)** | Settable price feed | [`0x3BBCfD7E67950265FD200c3e95195e8d92869646`](https://sepolia.arbiscan.io/address/0x3BBCfD7E67950265FD200c3e95195e8d92869646) |
| **TSLAx/USD feed (demo)** | Settable price feed | [`0x9d5304963C70b0842C2C911aff347b623E5ba7e4`](https://sepolia.arbiscan.io/address/0x9d5304963C70b0842C2C911aff347b623E5ba7e4) |
| **DemoLiquidityRouter** | v4 LP router exposing the real LP (like PositionManager) | [`0xf1Af071D389741ab0273cf26D61AF87D00c3CC5F`](https://sepolia.arbiscan.io/address/0xf1Af071D389741ab0273cf26D61AF87D00c3CC5F) |

**External contracts used**

| | Address |
|---|---|
| Uniswap v4 PoolManager (official) | [`0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`](https://sepolia.arbiscan.io/address/0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317) |
| 1inch Aqua, canonical (Arbitrum **One**) | `0x499943e74fb0ce105688beee8ef2abec5d936d31` |

**Markets:** USDG depeg from three underwriters (Genesis `0x60e5…7604`, B `0x4deb…b44d`, C `0xa500…000e`),
Uniswap v4 LP loss on wstETH/WETH (`0xe728…70ed`), and TSLAx gap-down (`0x895e…b02c`). v4 pool id
`0x9afa…71be`.

**Deployer / genesis underwriter:** [`0x204a73e8303F3d09B12062dEdAA74B1CDA6E167d`](https://sepolia.arbiscan.io/address/0x204a73e8303F3d09B12062dEdAA74B1CDA6E167d).
Underwriters B and C and the seed buyers are throwaway wallets derived from the deployer key. Full list and
redeploy notes: [`DEPLOYMENTS.md`](DEPLOYMENTS.md).

## 7. Tech stack & integration status

We keep this table honest: **live** means it runs in the demo flow today.

| Technology | Status | How it's used |
|---|---|---|
| **1inch Aqua** | ✅ **Live**, the reserve layer | Every market is an Aqua strategy: `ship` the reserve, `push` premiums, `pull` payouts. 1inch hasn't deployed Aqua on Arbitrum Sepolia, so we deployed their **unmodified** contract; the canonical Aqua on Arbitrum One is a drop-in for mainnet |
| **Uniswap v4** | ✅ **Live** | `CoverHook` on the official Arbitrum Sepolia PoolManager, with a real wstETH/WETH pool. The LP-loss product reads the hook |
| **Arbitrum Sepolia** | ✅ **Live** | 13 contracts deployed and source-verified |
| **USDG** | ✅ **Live (test token)** | Cover, premiums, payouts and reserves are all denominated in USDG. On testnet it's a mintable stand-in |
| **Price oracles** | 🟡 **Demo feeds live**, adapters built | The demo uses settable feeds so judges can trigger events. `ChainlinkOracleAdapter` and `PythOracleAdapter` (with staleness checks) are built for mainnet |
| **Keeper** | ✅ **Live** | `frontend/scripts/keeper.mjs`, permissionless, fires payouts and settles expiries |
| **Tokenomist** | ✅ **Integrated** (server key `TOKENOMIST_API_KEY`) | "Unlock watch" on the LP-loss product: upcoming cliff unlocks from the Tokenomist unlock-events API (`/api/unlocks`, cached an hour). An unlock moves the price, every pool holding the token takes an LP loss, so it is the moment to buy LP cover |
| Solvency book, tranches, cross-chain cover, futarchy pricing, hedge executor, slippage refund, verified-market registry | 🟡 **Built and tested, not in the live flow** | Plug-in products and reserve structures on the same engine (`ITrigger`, `IPremiumPricer`) |
| Frontend | ✅ | Next.js 16 + wagmi 3 + viem, MetaMask on Arbitrum Sepolia |
| Tooling | ✅ | Foundry (62 tests, invariant fuzzing), anvil demo chain with one-command reset |

## 8. Market fit

**Who it's for**

| Segment | Pain today | What Airbag gives them |
|---|---|---|
| **Stablecoin holders** (people, DAOs, treasuries) | A depeg can take 13% of their money overnight, and there's nothing to buy | Cheap parametric cover that pays in one block, automatically |
| **Payment, payroll & treasury apps** | Holding float in stablecoins is a risk they can't explain away | A "protect this balance" button inside their own product |
| **Liquidity providers** | Impermanent loss when a pair depegs (wstETH/WETH, stable pairs) | LP-loss cover bound to their v4 position |
| **RWA and tokenized-stock holders** | Gap risk at the open, around earnings or halts | Proportional gap-down cover |
| **Underwriters** (funds, market makers, yield seekers) | Idle stablecoins earn little; insurance pools lock capital | Premiums **plus** savings yield on capital that never leaves their wallet |

**Why now**
- **Regulated stablecoins are going mainstream** (USDG under MAS and MiCA), and they're being used as real money.
- **Pegs have broken before** (USDC at $0.87 in 2023), and holders now know it can happen.
- **Shared-liquidity rails exist.** 1inch Aqua makes non-custodial reserves practical, and Uniswap v4 hooks make
  on-chain loss measurement possible.

**Business model** (planned for mainnet)
- **Protocol fee on premiums**: a take rate on every policy sold; the rest goes to underwriters.
- **Distribution revenue share**: partners embedding the widget earn a share of the premiums they originate.
- **Keeper incentives**: a small payout tip for whoever fires a triggered policy.
- **Premium products**: custom triggers (`ITrigger`) for treasuries and RWA platforms.

**Go-to-market**
1. **USDG depeg cover on Arbitrum** as the wedge: simple to explain, simple to demo ("the airbag deploys itself").
2. **Widget distribution**: wallets, payment apps and RWA platforms sell cover at checkout.
3. **Underwriter program**: seed curves with market makers and savings-vault capital.
4. **More triggers**: LP loss, gap-down, and partner-defined events on the same engine.

**Competitive landscape**
- Discretionary cover mutuals pay after claims assessment and votes, and pool capital in custody.
- Prediction markets price events but aren't insurance: no automatic payout to a policy holder, no solvency floor.
- Airbag is **parametric, auto-paying, non-custodial and marketplace-priced**, all four at once.

## 9. Roadmap & milestones

| Milestone | Scope | Success metric |
|---|---|---|
| **M0 · Buildathon (done)** | 13 verified contracts on Arbitrum Sepolia · three cover products · automatic payouts · marketplace with 3 underwriters · yield-bearing reserves · console, widget and integrate page | Every flow works end to end on the live testnet |
| **M1 · Mainnet beta (≈ 6–8 weeks)** | Security review of `CoverApp`, `CoverRouter`, `CoverHook`, triggers · Arbitrum One on the canonical 1inch Aqua with real USDG · Chainlink / Pyth feeds · keeper tips · per-market caps · **reserve lock-up while cover is outstanding** | Beta live with capped capacity · first real premiums paid to underwriters |
| **M2 · Distribution (≈ 3 months)** | Widget partners (wallets, payment apps) · SolventBook aggregate floor on by default · tranched reserves for institutional underwriters | Premium volume · partner-originated share |
| **M3 · More risk (≈ 6 months)** | Position-sized LP cover · more assets and RWAs · cross-chain cover · governance for new triggers | Number of live triggers · retained underwriter capital |

## 10. Judging criteria

| Criterion | How Airbag addresses it |
|---|---|
| **Innovation & creativity** | Insurance that **pays itself**: a parametric trigger plus a permissionless keeper means no claim at all. Reserves that stay in the underwriter's wallet (Aqua) and earn yield while backing cover. A marketplace of underwriter risk curves. LP-loss cover measured by a v4 hook with a flash-loan guard |
| **Technical execution** | 62 tests including lifecycle, invariant fuzzing and a real v4 pool suite · 13 verified contracts live · on-chain solvency floor · atomic routed buys · no event-log dependence (state reads only) |
| **Real problem solving** | Stablecoin holders can't insure a depeg today, and existing cover pays slowly. Airbag pays in one block |
| **Product-market fit** | Clear buyers, a distribution wedge (the widget), an underwriter yield story and a fee model (see §8) |
| **USDG** | USDG is the insured asset, the premium, the reserve and the payout |
| **Arbitrum** | Built and deployed on Arbitrum Sepolia, mainnet-ready on Arbitrum One's live Aqua and v4 |

## 11. Run it locally

**Prerequisites:** Node ≥ 20, [Foundry](https://book.getfoundry.sh), and for testnet a browser wallet with a
little Arbitrum Sepolia ETH.

**Contracts**
```bash
cd airbag
forge build
forge test             # 62 tests in 13 suites
```
Setup note: `lib/` symlinks the 1inch libraries vendored under `../winner-usecases/liquid_OB` and Uniswap v4
from `../unizwap/contract/lib`; both are wired through `remappings.txt`.

**Full local demo** (anvil + every product + seeded book + keeper, one command)
```bash
cd airbag && ./demo-reset.sh
cd frontend && npm install && npm run dev      # http://localhost:3000/app
```
On the local chain the header has demo accounts (Buyer / Underwriter, no wallet needed) and a time machine, so
expiries and vault yield can be shown in seconds. Re-run `demo-reset.sh` for a clean slate.

**Against the live testnet**
```bash
cd airbag/frontend
npm run build && npm start          # production builds use the Arbitrum Sepolia addresses
```
Connect MetaMask, switch to Arbitrum Sepolia, click "Get test USDG" and buy cover.

**Deploy your own copy** (put `PRIVATE_KEY` and `ETHERSCAN_API_KEY` in `airbag/.env`)
```bash
POOL_MANAGER=0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317 forge script script/DeployDemo.s.sol \
  --rpc-url https://sepolia-rollup.arbitrum.io/rpc --private-key $PRIVATE_KEY --broadcast --slow
forge script script/AddMarketplace.s.sol --rpc-url https://sepolia-rollup.arbitrum.io/rpc \
  --private-key $PRIVATE_KEY --broadcast --slow
VERIFIER=sourcify ./verify-sepolia.sh
```

**Deploying the UI:** a standard Next.js app. Set the project root to `airbag/frontend`; no environment
variables are needed (optional: `NEXT_PUBLIC_RPC_URL`).

**Keep automatic payouts running during judging**
```bash
cd airbag && nohup ./keeper-sepolia.sh > /tmp/airbag-demo/keeper-sepolia.log 2>&1 &
```
It reads the key from `.env`, restarts itself on crashes, and keeps the demo price feeds fresh.

## 12. Repository layout

```
airbag/
├── src/                  Solidity (≈1,750 lines core, ≈3,000 with vendored curve maths and mocks)
│   ├── CoverApp · CoverNote · CoverRouter · CoverHook · YieldReserve · SolventBook · TranchedReserve
│   ├── triggers/         ILTrigger · PriceGapTrigger · SlippageRefundTrigger · BookSolvencyTrigger
│   ├── libraries/        RiskCurve · CurveKernelPricer
│   ├── oracles/          Chainlink + Pyth adapters
│   └── crosschain/ futarchy/ hedge/ registry/ mocks/
├── test/                 Foundry tests (13 suites, 62 tests)
├── script/               DeployDemo · AddMarketplace · Deploy · DeployHook
├── frontend/             Next.js app: landing, console, widget, integrate · scripts/keeper.mjs
├── demo-reset.sh         One-command local demo
├── keeper-sepolia.sh     Self-restarting testnet keeper
├── verify-sepolia.sh     Sourcify / Arbiscan verification
└── DEPLOYMENTS.md        Addresses, markets, redeploy notes
```

## 13. Security, limits & honest caveats

- **Testnet only, not audited.** Don't use it with real funds. A security review is milestone M1.
- **Reserves aren't locked.** Aqua lets an underwriter `dock` a market at any time, even with cover outstanding.
  Solvency is **checkable on-chain**, not enforced after the fact. A lock-up while cover is outstanding is on
  the M1 roadmap.
- **Shared reserves can be double counted.** Aqua balances are virtual, so one wallet can back several markets
  with the same USDG. The `SolventBook` aggregate floor handles this but is off in the demo.
- **LP-loss cover is an index.** It pays a share of the policy notional based on the pool's IL; the notional
  isn't capped by the size of the LP's position.
- **Testnet stand-ins:** test USDG, settable price feeds (so judges can trigger events), a demo savings vault,
  our own copy of 1inch's unmodified Aqua, and throwaway wallets for the extra underwriters and seed buyers.
- **Keeper liveness:** automatic payouts need a keeper running. If none is, holders can still `claim()`
  themselves, and anyone can fire `payout()`.
- **Bugs found and fixed during the build:** premiums first ignored the policy term (a 5-minute policy cost the
  same as a 30-day one); they are now an annual rate × term, with a test. Expired policies originally locked
  capacity forever; `expire()` now releases it, covered by the lifecycle suite.

## 14. Further reading

- [`DEPLOYMENTS.md`](DEPLOYMENTS.md): contracts, markets and redeploy history
- [`frontend/README.md`](frontend/README.md): running the app, the demo script and the keeper
- [`../airbag-insurance-protocol.md`](../airbag-insurance-protocol.md): protocol design
- [`../airbag-submission-brief.md`](../airbag-submission-brief.md) · [`../arbitrum-buildathon-winplan.md`](../arbitrum-buildathon-winplan.md): positioning notes

Solidity sources are MIT-licensed (SPDX headers), except the vendored ArcBook curve kernel under `src/curve/`
(AGPL-3.0, attributed).
