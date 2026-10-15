# Airbag — deployments

## Arbitrum Sepolia (421614) — v3 (2026-10-15)

Deployed with `script/DeployDemo.s.sol` + `script/AddMarketplace.s.sol`. Deployer / genesis underwriter `0x204a73e8303F3d09B12062dEdAA74B1CDA6E167d`.

**Verification:** all 13 contracts are verified on **Arbiscan** and **Sourcify (exact match)** (`./verify-sepolia.sh`, `VERIFIER=sourcify ./verify-sepolia.sh`).

| Contract | Address | Notes |
|---|---|---|
| CoverApp | [`0xe7ed61808A361f60a767Bb2e4625D565E17fc9d9`](https://sepolia.arbiscan.io/address/0xe7ed61808A361f60a767Bb2e4625D565E17fc9d9) | markets, annual-rate premiums, payout / claim / expire |
| CoverRouter | [`0x11A85418636801774ACeFb7a9C67c70c3d4127F0`](https://sepolia.arbiscan.io/address/0x11A85418636801774ACeFb7a9C67c70c3d4127F0) | marketplace: atomic multi-underwriter routes |
| CoverNote | [`0xE04704211f2D3015031762F7d95e8ddC1d60a5e7`](https://sepolia.arbiscan.io/address/0xE04704211f2D3015031762F7d95e8ddC1d60a5e7) | ERC-6909 policy notes (holderOf → auto-payout) |
| ILTrigger | [`0x1ceE0DbeA55eC5C545b243d6901de7197dD9Ce56`](https://sepolia.arbiscan.io/address/0x1ceE0DbeA55eC5C545b243d6901de7197dD9Ce56) | Uniswap v4 LP-loss payouts |
| PriceGapTrigger | [`0x480C8BA3f8BDCdc2d59F21dd9181CFF05b5C678B`](https://sepolia.arbiscan.io/address/0x480C8BA3f8BDCdc2d59F21dd9181CFF05b5C678B) | stock gap-down payouts |
| CoverHook (Uniswap v4) | [`0x8d9FfDe2ABe7fB498Cf44692eD4DEF990D698Ac0`](https://sepolia.arbiscan.io/address/0x8d9FfDe2ABe7fB498Cf44692eD4DEF990D698Ac0) | LP entry/exit, IL math, block-open tick guard |
| v4 PoolManager (Uniswap, official) | [`0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317`](https://sepolia.arbiscan.io/address/0xFB3e0C6F74eB1a21CC1Da29aeC80D2Dfe6C9a317) | Arbitrum Sepolia deployment |
| Aqua (1inch, unmodified copy) | [`0x6Ec59Cf8522A0Ca19bca3097CB0fa8fE363231A6`](https://sepolia.arbiscan.io/address/0x6Ec59Cf8522A0Ca19bca3097CB0fa8fE363231A6) | 1inch hasn't deployed Aqua on Arb Sepolia — canonical 0x4999…6d31 is on Arbitrum One |
| YieldReserve | [`0xe589036Cc53ad999edeB2455A4D7618Da7Ea081a`](https://sepolia.arbiscan.io/address/0xe589036Cc53ad999edeB2455A4D7618Da7Ea081a) | genesis depeg maker: reserve earns vault yield, JIT withdraw on payout |
| Savings vault (demo, 4.5% APR) | [`0x31F77137213547BDB67937ab62d5FcA2561a87f0`](https://sepolia.arbiscan.io/address/0x31F77137213547BDB67937ab62d5FcA2561a87f0) | DripVault |
| USDG (demo, mintable) | [`0x08Fa806EC09e631EF271E15bD025542Ef812e8a3`](https://sepolia.arbiscan.io/address/0x08Fa806EC09e631EF271E15bD025542Ef812e8a3) | test USDG |
| USDG/USD feed (demo) | [`0x3BBCfD7E67950265FD200c3e95195e8d92869646`](https://sepolia.arbiscan.io/address/0x3BBCfD7E67950265FD200c3e95195e8d92869646) | settable |
| TSLAx/USD feed (demo) | [`0x9d5304963C70b0842C2C911aff347b623E5ba7e4`](https://sepolia.arbiscan.io/address/0x9d5304963C70b0842C2C911aff347b623E5ba7e4) | settable |
| wstETH/WETH LP router | [`0xf1Af071D389741ab0273cf26D61AF87D00c3CC5F`](https://sepolia.arbiscan.io/address/0xf1Af071D389741ab0273cf26D61AF87D00c3CC5F) | IMsgSender router (like PositionManager) |
| v4 swap router (test) | [`0xCBBe54a8Eeb77427ba8aC7f7A8f700cBFDdBd858`](https://sepolia.arbiscan.io/address/0xCBBe54a8Eeb77427ba8aC7f7A8f700cBFDdBd858) | used by the depeg-shock button |

| Market | strategyHash |
|---|---|
| USDG depeg — genesis (reserve in savings vault, 1%→10%/yr) | `0x5c59a02948a7710d3c74258935c2e05b5725f9c946aef5628fc40b5e84e4f784` |
| USDG depeg — underwriter B (0.6%→14%/yr, k 2.5, 400k) | see `CoverApp.marketList(3)` |
| USDG depeg — underwriter C (1.5%→6%/yr, k 1, 600k) | see `CoverApp.marketList(4)` |
| Uniswap v4 LP loss (wstETH/WETH) | `0xcbcf1ce58298ae7de6b785b212685a1d359060f60a5dcf5334b646383d6511c5` |
| TSLAx gap-down | `0x998a0e62d1d4a098fc892144fc30a4cf4e6d1da966857acf6c0f1760e0dd3ffb` |

v4 pool id `0x19e0d3a0e511a554c603636937a87f28aacf887ccd050f7625c13a0510d95b44`.

Seeded book: 4 policies from 3 throwaway wallets; underwriters B and C are throwaway wallets too (all derived from the deployer key and funded with a little gas).

**v3** (2026-10-15) is a fresh run of the same two scripts and replaces v2 (2026-09-28); the code adds the protocol fee (off: `protocolFeeBps` = 0) and the LP-first demo. **v1** (2026-09-28, superseded): premiums were per-policy regardless of term; v2 onward prices them as annual rates × term.

**Honest notes:** USDG, the two price feeds and the savings vault are demo stand-ins on testnet. Aqua is 1inch's unmodified contract, deployed by us because it isn't on Arbitrum Sepolia.

## Keeper

```bash
nohup ./keeper-sepolia.sh > /tmp/airbag-demo/keeper-sepolia.log 2>&1 &
```
Reads `PRIVATE_KEY` from `.env`, restarts on crashes; `DEMO_FEED=1` keeps the demo price feeds fresh like a live oracle.
