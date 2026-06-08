# The Moonpot — How the System Works

A plain-language walkthrough with example numbers. Figures reflect the contract
configuration: **28 rounds**, prices escalating $1.15 → $2.10.

---

## What you get when you participate

- **TMP** — the token. It trades on Uniswap and has a **hard price floor** that
  starts at **$1.15** and ratchets up to **$2.10** by the final round (the price
  can never go below the current floor).
- **Prize NFTs** — lottery tickets. Each reveals, via Chainlink VRF, into a USDC
  prize. The prize ladder scales with the round (top prize $100,000 in Round 1, up
  to **$100,000,000** in Round 28).

You get both when you mint.

---

## The round schedule (28 rounds)

Each round sells a larger allocation, and **must fully sell out before the next
opens.** Community share is a flat **$1.00/token**, so each round's prize pool =
$1.00 × its allocation.

| Round | Price | Allocation (TMP) | Prize pool |
|---:|:--:|---:|---:|
| 1–9 | $1.15 | 1M → 9M | $1M → $9M |
| 10 | $1.20 | 10M | $10M |
| 11–19 | $1.20 | 20M → 100M | $20M → $100M |
| 20 | $1.30 | 200M | $200M |
| 21 | $1.40 | 300M | $300M |
| 22 | $1.50 | 400M | $400M |
| 23 | $1.60 | 500M | $500M |
| 24 | $1.70 | 600M | $600M |
| 25 | $1.80 | 700M | $700M |
| 26 | $1.90 | 800M | $800M |
| 27 | $2.00 | 900M | $900M |
| 28 | $2.10 | 1,000M | $1,000M |

**Full-program totals:** ~6B TMP sold → **~$10.5B raised**, of which **~$6B** is
paid out in prizes, **~$3.9B** flows into the floor liquidity, and **~$600M** to
the company.

---

## Where your money goes

Every mint splits three ways. The **prize pool ($1.00/token)** and **company
($0.10/token)** are constant — the **price increase in later rounds goes entirely
into liquidity**, which deepens the floor.

| Tier | Price | Prize pool | Company | Liquidity (floor) |
|---|:--:|--:|--:|--:|
| Rounds 1–9 | $1.15 | $1.00 | $0.10 | $0.05 |
| Rounds 10–19 | $1.20 | $1.00 | $0.10 | $0.10 |
| Round 20 | $1.30 | $1.00 | $0.10 | $0.20 |
| … | … | $1.00 | $0.10 | … |
| Round 28 | $2.10 | $1.00 | $0.10 | $1.00 |

So the floor doesn't just hold — it gets **structurally stronger every round**, and
the priciest, largest rounds pour the most USDC into it.

---

## The lifecycle, step by step

### 1. Launch (one-time)
The pool is deployed and seeded with USDC. It opens **~13% above the floor**
(~$1.30) so the seed USDC sits *underneath* the price as a **buy-wall** down to the
floor.

### 2. Mint (while a round is open)
You pay the round price per TMP and receive TMP plus prize NFTs.

> **Example (Round 1):** mint **1,000 TMP for $1,150** and receive **~100 prize
> NFTs** (Round 1 issues 99,991 NFTs across 1,000,000 TMP). Your $1,150 splits into
> $1,000 prize pool · $100 company · $50 liquidity.

### 3. Reveal (Chainlink VRF)
Once your purchase is processed, Chainlink VRF randomly assigns each NFT a **prize
class**. Each round has the same 16-class shape (99,991 NFTs), with prizes scaled to
that round's pool. Round 1's table:

| Class | Prize (Round 1) | # of NFTs |
|------:|----------------:|----------:|
| 1 | $100,000 | 1 |
| 2 | $50,000 | 2 |
| 3 | $25,000 | 3 |
| 4 | $10,000 | 5 |
| 5 | $5,000 | 10 |
| 6 | $2,500 | 20 |
| 7 | $1,000 | 50 |
| 8 | $500 | 100 |
| 9 | $250 | 300 |
| 10 | $100 | 500 |
| 11 | $50 | 1,000 |
| 12 | $25 | 3,000 |
| 13 | $10 | 5,000 |
| 14 | $5 | 10,000 |
| 15 | $2.50 | 30,000 |
| 16 | $1 | 50,000 |
| **Total** | **$1,000,000** | **99,991** |

Later rounds multiply every prize by `allocation ÷ 1M` — so Round 28's table runs
$1,000 → $100,000,000 (same 99,991 NFTs, pool $1B).

### 4. Claim
After the round reveals, you redeem each NFT for its USDC prize.

### 5. Trade (anytime)
TMP trades on Uniswap. Buying pushes the price up; selling pushes it toward the
**current floor**, which is defended:

- **Sell tax** is steep near the floor (**up to 50%**) and tiny far above it
  (**0.3%**). It discourages dumping into the floor and feeds the pool.
- **Burn cap:** you can only sell as much as the pool can absorb down to the floor.
  Anything beyond that is **burned** instead of sold.

> **Real example (test swap):** a seller submitted **1,000 TMP**. The pool took
> **792 TMP** (the most it could absorb) and paid out USDC; the remaining **207 TMP
> were burned**. The seller got fair value for what could be sold, and the floor
> held.

### 6. Repeat across rounds
Twenty-eight rounds, with rising prices and prize pools. **The floor ratchets up
($1.15 → $2.10), and each round adds more USDC to it than the last.**

### 7. After all rounds (distribution complete)
- **The floor stays at $2.10** — sells below it are 100% burned, so the price cannot
  fall under it.
- **Deflation** — every dump and every fee harvest **burns TMP**, so supply only
  shrinks; the USDC backing is spread over fewer and fewer tokens.
- **Fees** — trading fees accrue to the pool; on harvest, the TMP portion is burned
  and the USDC portion goes to the company (which may do **discretionary buybacks**).

The protocol *guarantees the floor and shrinks supply*; price appreciation above the
floor comes from real market demand.

---

## Why the floor money can't be drained for profit

> **USDC only leaves the pool when someone sells TMP into it — and TMP can never be
> bought below the current floor.**

So to pull a dollar of floor USDC out, you must first buy TMP at **≥ the floor**,
then sell it back **at the floor** — paying a **35–50% sell tax** on the way down
against a gap of at most ~13%. Every attempt is a **guaranteed loss**. The floor
liquidity is exit liquidity for holders, not a pot an attacker can crack — and the
same logic protects the USDC added during every round.
