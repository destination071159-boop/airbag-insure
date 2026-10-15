# Airbag: step by step

How one policy lives, from the underwriter's setup to the payout or the expiry. The example is the one
from the pitch: Alice insures 50,000 USDG for 7 days and pays 6.99 USDG.

## The whole flow

```mermaid
sequenceDiagram
    autonumber
    actor U as Underwriter
    participant V as Savings vault
    participant Q as 1inch Aqua
    participant A as Airbag
    actor B as Buyer (Alice)
    participant O as Price feed
    participant K as Payout bot

    Note over U,A: Setup, before any buyer arrives
    U->>V: Put 1,000,000 USDG in own yield reserve
    V-->>U: Interest starts
    U->>Q: Promise the reserve (money stays with the underwriter)
    U->>A: Open a market (trigger 0.97, price curve, capacity)

    Note over A,B: Buying cover
    B->>A: Ask for a quote (50,000 USDG, 7 days)
    A->>A: Find the cheapest underwriters
    A-->>B: Fee is 6.99 USDG
    B->>A: Pay 6.99 USDG
    A->>Q: Check the reserve and the room left
    A->>U: Pass on the whole fee
    A-->>B: Cover note (a token)

    Note over U,K: While the cover runs
    V-->>U: Interest keeps coming
    loop Every few seconds
        K->>O: Read the price
        K->>A: Read the open policies
    end

    alt The peg breaks inside 7 days
        O-->>K: Price is 0.92
        K->>A: Fire the payout
        A->>O: Read the price and check it is fresh
        A->>A: 0.92 is at or below 0.97, pay 100%
        A->>V: Withdraw 50,000 from the vault
        A->>Q: Pull 50,000 from the underwriter
        Q-->>B: 50,000 USDG arrives
        Note over B: Alice did nothing
    else Nothing happens for 7 days
        K->>A: Mark the policy as expired
        A->>A: Free 50,000 of capacity
        Note over U: The underwriter keeps the fee and the interest
        Note over B: The cover note is now worthless
    end
```

## The same flow, one part at a time

### 1. The underwriter sets up

```mermaid
sequenceDiagram
    autonumber
    actor U as Underwriter
    participant V as Savings vault
    participant Q as 1inch Aqua
    participant A as Airbag

    U->>V: Put the reserve in own yield reserve
    V-->>U: Interest starts
    U->>Q: Give permission to pull the reserve when a payout is owed
    U->>A: Open a market
    Note over U,A: Trigger line, price curve, share of the reserve that may be sold
    Note over U: The money never moves into Airbag
```

### 2. The buyer buys cover

```mermaid
sequenceDiagram
    autonumber
    actor B as Buyer
    participant A as Airbag
    participant Q as 1inch Aqua
    actor U as Underwriter

    B->>A: Choose product, amount and days
    A->>A: Read every price curve, build the cheapest mix
    A-->>B: Show the fee
    B->>A: Pay the fee in one transaction
    A->>Q: Is the reserve really there, and is there room
    Q-->>A: Yes
    A->>U: Whole fee goes to the underwriter
    A-->>B: Cover note
    Note over A: The market is now fuller, so the next buyer pays a little more
```

### 3a. The trigger fires

```mermaid
sequenceDiagram
    autonumber
    participant O as Price feed
    participant K as Payout bot
    participant A as Airbag
    participant V as Savings vault
    participant Q as 1inch Aqua
    actor H as Holder of the cover note

    O-->>K: Price is 0.92
    K->>A: Fire the payout (anyone may call this)
    A->>A: Policy still running and not paid yet
    A->>O: Read the price, reject it if stale
    A->>A: At or below the trigger line, pay 100%
    A->>A: Destroy the cover note
    A->>V: Withdraw exactly the payout
    A->>Q: Pull the payout from the underwriter
    Q-->>H: 50,000 USDG arrives
```

### 3b. Nothing happens

```mermaid
sequenceDiagram
    autonumber
    participant K as Payout bot
    participant A as Airbag
    actor U as Underwriter
    actor B as Buyer

    Note over A: 7 days pass and the price stays above 0.97
    K->>A: Mark the policy as expired (anyone may call this)
    A->>A: Free the capacity for new buyers
    Note over U: Keeps the fee and the interest, reserve untouched
    Note over B: Paid 6.99 for a week of protection, receives nothing
```

## Who ends up with what

| | Peg breaks | Nothing happens |
|---|---|---|
| Buyer | Paid 6.99, received 50,000 | Paid 6.99, received nothing |
| Underwriter | Received 6.99 plus interest, paid 50,000 | Keeps 6.99 plus interest |
| Airbag | Its share of the 6.99, if a fee is set | Its share of the 6.99, if a fee is set |

## Things the diagrams do not show

- **Events are recorded when they are seen.** Anyone (in practice the payout bot) calls `poke` on a
  market. While the trigger is true it records an episode; when it is false again, it closes it. A
  policy whose cover saw an episode begin is paid for it, even after the price has recovered, and up
  to 3 days after the policy expired. A dip that nobody recorded and that is already over still pays
  nothing.
- **No cover for an event already under way.** Buying is refused while the trigger is true, and while
  a recorded episode has not been seen to end.
- **Proportional payouts top up.** For the stock and LP products, a payout fired early is not final:
  if the loss deepens later in the term, the difference is paid then. The policy closes once it has
  paid in full or its term is over.
- **The reserve is not locked.** The underwriter can move their money at any time. Airbag then stops
  selling their cover, but a payout on cover already sold would fail.
- **Airbag can keep a share of each premium.** The owner sets the share (20% at most) and where it
  goes. It is taken out of the premium, so the buyer's price does not change and the underwriter
  receives the rest. Payouts are never charged. The share is 0 until the owner sets it, and the
  contracts live on Arbitrum Sepolia were deployed before this existed, so they take no fee.
- **The underwriter sets buying rules.** `setBuyRules` sets the shortest and longest term their market
  sells and a waiting period before cover starts (0 = none). The term starts after the wait, and an
  event that began during the wait is not covered.
- **Not live yet.** The fee, the buying rules, recorded events and top-ups are in the code and tested,
  but the contracts live on Arbitrum Sepolia were deployed before them.
- **The other two products work the same way** with a different trigger: a Uniswap v4 hook measures a
  liquidity provider's loss, and a price feed measures a stock's fall. Both can pay a share of the
  cover, where the depeg always pays all of it.
