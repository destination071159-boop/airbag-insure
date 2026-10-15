# Airbag pitch runbook (U-Hackathon, 15–16 Oct 2026)

For whoever presents Airbag. Files in this folder:

| File | Use |
|---|---|
| `airbag-pitch.html` | The deck. Open it in a browser. Each click reveals the next piece. Works with no internet. |
| `airbag-pitch.pdf` | The same 12 slides as a PDF, for sending to judges or as a backup. |
| `diagrams/` | The two hand-drawn diagrams in the deck, plus a depeg pair for questions. |
| `RUNBOOK.md` | This file: the live demo, the reset, and answers to hard questions. |

Deck keys: click, `→` or space = next · `←` or right-click = back · `F` = full screen · `N` = speaker notes
(they show on the same screen, so judges see them too on a projector).

The deck tells the **Uniswap v4 LP loss** story, so the demo shows LP cover. The timings below come from
earlier runs of each step; **rehearse the whole flow on the redeployed contracts on 15 Oct** and correct them.

## Before you go on stage

1. **Wallet.** MetaMask on **Arbitrum Sepolia**, with test ETH for gas (0.05 ETH covers several runs; the LP flow
   sends more transactions than the depeg flow). Use a wallet with no old Airbag policies so the screen starts clean.
2. **Open** <https://airbag.insure/app> and connect. Keep the deck in another tab.
3. **Product 01 · LP loss** is selected when the console opens. Check the wstETH/WETH pool price reads about **1.000**. If it shows the crash,
   press **Restore peg** and wait for it to settle. Cover bought during a crash measures from the crashed price
   and pays nothing.
4. **Do the slow setup off stage.** Press **Get test USDG**, then **Become an LP →** (it mints test wstETH and WETH,
   approves them and adds liquidity: up to five wallet pop-ups, about 35 s). The "Your LP position" row then shows
   **live** with IL 0.00%. Becoming an LP is not the point of the demo; buying cover is.
5. **Check the keeper.** The automatic payout needs the keeper bot running. It runs on Kongphop's laptop
   (`./keeper-sepolia.sh` in `airbag/`). Ask him to confirm it is running, on the **new** deployment, before your slot.
   If it is not, you can still finish the demo: see "If something goes wrong".

## The live demo (about 2 minutes)

| # | Click | Wait | Say |
|---|---|---|---|
| 1 | Show the **Your LP position** row | none | "I'm a liquidity provider in a real Uniswap v4 pool, wstETH against WETH. Our hook records where I entered." |
| 2 | **100k**, term **7 days** | none | "I buy a hundred thousand of cover. It pays from 0.5% of loss, and in full at 5%." Point at the "You pay" card. |
| 3 | **Buy + link LP cover · … USDG →** | ~20 s | "Two transactions: buy the cover, and link it to my position. The loss is measured from this moment, so you can't insure a crash that already happened." |
| 4 | **wstETH depeg −33%** in the pool panel | ~20 s | "Now a real swap dumps wstETH into the pool. My position is worth less than if I had just held the tokens." The row shows IL ≈ 2%. |
| 5 | Nothing. Scroll to the top. | ~20 s | "We do nothing. The hook measured the loss, and the keeper fires the payout." The green **Paid ✓** banner shows about **32,900 USDG**. |
| 6 | **Restore peg** | ~20 s | Do this straight away so the next presenter or judge starts from a calm pool. |

How the number works, if asked: −33% gives about 1.98% impermanent loss. The cover pays
(1.98% − 0.5%) ÷ (5% − 0.5%) ≈ 32.9% of 100,000. The deck's Alice example uses a bigger move (−40%, 3.18% loss),
so say "a smaller crash than on the slide" rather than expecting the slide's numbers.

The payout is proportional, so the policy **stays open** after it: if the loss deepened before expiry, the
keeper would pay the difference. The policy row shows "paid … · still covered".

**If you have another minute**, pick one of these, not all three:

- **Depeg cover (fast, ~40 s):** product **02 · Stablecoin depeg** → **50k**, **7 days** → **Buy cover** (~11 s) →
  **Depeg → $0.92** → the banner shows 50,000 USDG within about 20 s → **Reset $1.00**. Good for showing the
  router splitting one order across underwriters.
- **Widget:** open **Integrate** in the top bar and show the "Protect this balance" widget.
- **Underwrite:** tab **Underwrite** → show the risk-curve editor and drag it. Do **not** press
  "Ship reserve + open market" on stage or in rehearsal: every new market stays in the order book for good.

## After each run

Press these in the app. No scripts or keys are needed:

- **Restore peg** (pool panel, after the LP crash)
- **Exit** on the LP position row, if the next run should start from a fresh position
- **Reset $1.00** (only if you ran the depeg demo)
- **Reset $250** (only if you moved the stock price)

Each payout takes money out of the underwriters' reserves. After many runs the quotes drift and orders split
across more underwriters. Kongphop can refill the reserves with the deployer key
(`.claude/skills/airbag-demo-video/scripts/reset-demo.sh`, which is on his laptop and not in the repo).
Ask him to run it once on the morning of the pitch.

## If something goes wrong

| Problem | What to do |
|---|---|
| No payout banner after 30 seconds | The keeper is not running. Open the **Keeper** tab and press **Run a keeper round**, or press **Claim now** on the policy row. Say: "Anyone can fire the payout. Here I do it by hand." |
| "Buy + link" is greyed out | You are not an LP yet. Press **Become an LP →** first. |
| The crash button is greyed out | The pool is still crashed from an earlier run. Press **Restore peg**, wait, then buy cover again. |
| The payout is zero or the keeper skips it | The cover was linked while the pool was crashed, so the loss is measured from the crashed price. Restore the peg, buy and link new cover, then crash again. |
| A transaction hangs | Arbitrum Sepolia is slow sometimes. Wait 30 seconds, then refresh the page. Your cover notes are still there. |
| The site or the network is down | Play the video (`demo-video/airbag-demo.mp4` on Kongphop's laptop, or the YouTube link in the README) and talk over it. The video shows the depeg flow; say "same engine, different trigger". |

## Hard questions and honest answers

**Is the price feed real?**
No. On testnet the feeds are demo feeds that anyone can set, which is how we trigger a depeg on stage. Adapters
for Chainlink and Pyth with staleness checks are written, but they are not connected in the live demo.

**Can one wallet back several markets with the same money?**
Yes. Aqua balances are virtual, so the same USDG can be promised to more than one market. A contract that
enforces one floor across all of a wallet's markets (`SolventBook`) is built and tested, but it is switched
off in the demo.

**Can an underwriter take the reserve out while cover is open?**
Yes. Aqua lets them withdraw at any time. Solvency can be checked by anyone on-chain, but it is not locked.
A lock-up while cover is outstanding is the first item on the roadmap.

**What stops a market selling more cover than it can pay?**
Every purchase checks that cover in force stays under the reserve times a set limit, and reverts if not.
A payout pulls the money from the underwriter's wallet in the same transaction and reverts if it is not there.

**What if the keeper is down?**
The payout function is open to everyone. The holder can claim it themselves, and anyone else can fire it.

**Is that really 1inch Aqua?**
It is 1inch's contract, unmodified. 1inch has not deployed Aqua on Arbitrum Sepolia, so we deployed a copy.
On Arbitrum One the official one would be used.

**Is that real USDG?**
No. It is a test token that anyone can mint. The savings vault (4.5% a year) is also a demo contract.

**Is the LP cover exact?**
It is an index. It pays a share of the cover amount based on the pool's loss, and the amount is not capped
by the size of your position.

**Is it audited?**
No. It is testnet only.

**How do you make money?**
A protocol fee taken out of each premium, capped at 20% in the contract. It is built and tested; whether it is
switched on depends on the 15 Oct redeploy (check `protocolFeeBps` on CoverApp). A share for apps that embed the
widget is planned, not built.

**Did you build this at the hackathon?**
No. Airbag was built in September and early October 2026 for the Arbitrum Open House buildathon. Say this
plainly if asked, and check the event's rule on existing projects before the pitch.

## Numbers used in the deck

| Claim | Source |
|---|---|
| 49.5% of Uniswap v3 LPs did worse than holding | Loesch et al., "Impermanent Loss in Uniswap v3", Bancor & Topaze Blue, 2021 ([arXiv 2111.09192](https://arxiv.org/abs/2111.09192)). Pools over $10M TVL, May–Sep 2021. Bancor sells IL protection, so mention it if asked. |
| $260M impermanent loss against $199M fees | Same study |
| Less than 2% of DeFi value is insured | bex.co, May 2026 (link in `README.md`, section 1) |
| Alice: $4,500 cover, −3.18%, +$2,675 | Worked from the LP market's settings (0.5% deductible, 5% cap). An illustration, not a live run. |
| About $7 premium for 30 days | The LP market's curve starts at 2% a year: 4,500 × 2% × 30/365 ≈ 7.40. Not a screen quote. |
| 13 contracts, source-verified | `DEPLOYMENTS.md`: v3 redeploy 15 Oct, all 13 verified on Arbiscan + Sourcify. |
| 62 tests passing | `forge test`, 13 suites, the deployed v3 code (15 Oct). |
| 30 seconds from crash to LP payout | Measured on the v3 contracts on 15 Oct 2026 (`demo-video/lp-check.mjs`): 29.6 s from the confirmed −33% wstETH shock to "Paid ✓" for 100k LP cover (32,880 USDG paid). The depeg payout in the same run took 11.0 s. Both depend on the keeper and the network. |
