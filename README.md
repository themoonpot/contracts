# The Moonpot Contracts

Solidity 0.8.28 contracts for The Moonpot: a multi-round token sale that mints **TMP** (ERC20) and **TMPNFT** (ERC721A) per purchase, assigns each TMPNFT a deterministic USDC redemption value via a Chainlink VRF v2.5 round seed, and seeds a Uniswap v4 pool with a custom hook that enforces a price floor and dynamic anti-dump tax.

## Architecture

```
                ┌────────────────────────────┐
       USDC ──▶ │       MoonpotManager       │ ◀── Chainlink VRF v2.5
                │  (orchestrator, rounds,    │
                │   purchases, NFT claims)   │
                └─────┬──────────┬─────┬─────┘
                      │ mint     │     │ start/end/seed
                      ▼          ▼     ▼
              ┌──────────┐  ┌────────┐  ┌──────────────────┐
              │ TMP      │  │ TMPNFT │  │ MoonpotRound1..N │
              │ (ERC20)  │  │(ERC721A)│ │ (value tables,   │
              └────┬─────┘  └────────┘  │  TEA permutation)│
                   │                    └──────────────────┘
                   │ mint/burn
                   ▼
              ┌──────────────────────────────┐
              │        MoonpotHook           │ ◀── Uniswap v4 PoolManager
              │ (price-floor + dynamic tax,  │
              │  liquidity injection, fee    │
              │  harvest)                    │
              └──────────────────────────────┘
```

Every USDC paid for TMP is split three ways by the active round, in fixed
proportions across all rounds (only the per-token price changes between
rounds):

| Share           | Per token (USDC)         | Destination                    |
| --------------- | ------------------------ | ------------------------------ |
| Community       | `PRICE − $0.15`          | Round contract → reward pool   |
| Company         | $0.10                    | Company treasury (immediate)   |
| Liquidity       | $0.05                    | Hook (queued for LP injection) |
| **Token price** | **$1.15 → $2.10**        |                                |

## Contracts

### Core

#### [`MoonpotToken.sol`](MoonpotToken.sol): `TMP`

ERC20 (`"The Moonpot Token"`, `TMP`) with `Ownable2Step`. Only the
one-time-set `manager` (the `MoonpotManager`) can `mint`. Anyone holding TMP
can `burn` their own balance.

#### [`MoonpotNFT.sol`](MoonpotNFT.sol): `TMPNFT`

ERC721A (`"The Moonpot NFT"`, `TMPNFT`) with `ERC721AQueryable` and
`Ownable2Step`. Only the manager can `mintTo`. The round ID is stamped into
the ERC721A `extraData` on the first token of each batch and read back via
`getRound(tokenId)` to look up the reward table at redemption time. The base URI can
be rotated by the owner (emits `BatchMetadataUpdate`) until `freezeBaseURI()`
is called.

#### [`MoonpotManager.sol`](MoonpotManager.sol)

Single source of truth. Owns the lifecycle of up to `MAX_ROUNDS = 28` rounds.

- **`init(usdcAmount, ceilingTick)`**: one-shot. Mints the initial TMP, builds
  the Uniswap v4 `PoolKey`, opens a wide LP position via `permit2` +
  `IPositionManager.multicall` (bundles `initializePool` + `MINT_POSITION` +
  `SETTLE_PAIR`), burns leftover TMP, and registers the position with the hook.
  Initial sqrt price is set `INIT_TICK_PREMIUM = 1200` ticks above the round-1
  floor.
- **`setRound(id, addr)`**: wires round contracts in (one-shot per id).
- **`start()`**: starts round 1, or rolls forward to the next round once the
  current one has ended. Updates the hook's `currentFloorTick` to the new
  round's price.
- **`buyFor(buyer, usdcAmount, deadline, v, r, s)`**: entry point for
  purchases. Pulls USDC (with a best-effort `permit` if allowance is
  insufficient), routes shares, mints `tokens * 1e18` TMP to the buyer,
  requests a VRF word for the purchase's NFT allocation, and emits
  `PurchaseCommitted`. Capped at `MAX_PURCHASE_LIMIT = 10_000` tokens per call.
  Calls `_maybeInjectLiquidity` (every 1/40th of a round's supply) and
  `_maybeEndRound` (when the round sells out).
- **`processBuy(purchaseId)`**: once VRF has filled the purchase seed
  (`isDrawn`), allocates NFTs by walking `tmpAmount` Bernoulli trials against
  the remaining ratio `nftsLeft / drawsLeft`. Mints the resulting count of
  TMPNFTs to the buyer and notifies the round.
- **`claimNFT(tokenId)` / `claimNFTs(tokenIds[])`**: after a round has ended
  AND been seeded by VRF, NFT holders compute their token's USDC value via
  the round's `valueOf(tokenId)` (deterministic from the round seed) and
  `releaseReward` USDC out of the round's pool. `claimNFTs` batches by round.
- **`reDrawPurchase(purchaseId)`**: anyone can re-request a stuck purchase
  VRF allocation after `VRF_TIMEOUT = 24h`; the owner can re-request immediately.
- **`retryRoundReveal(roundId)`**: owner-only re-request of the round seed.
- **VRF callbacks**: `fulfillRandomWords` dispatches by `VRFRequestType`
  (`Purchase` → set purchase seed; `Round` → set round seed).
- **Liquidity ramp**: every 2.5% of a round's supply sold, all queued
  liquidity USDC is injected into the LP. The manager mints just enough TMP to
  the hook to pair with the USDC at the current sqrt price (with a 1% buffer
  that the hook burns).

#### [`MoonpotHook.sol`](MoonpotHook.sol)

Uniswap v4 hook (`BaseHook`) attached to the TMP/USDC pool. Implements
`beforeInitialize` and `beforeSwap` (with delta + dynamic fee).

- **Price-floor defense**: on every TMP→USDC swap, the hook reads the current
  tick, clamps the user's sell to a `_computeMaxTmpSell` amount that would not
  push price below the round's `floorTickLower/Upper`, and **burns the
  excess TMP** (taken via `poolManager.take` and burned through
  `MoonpotToken.burn`). Exact-output TMP sells are blocked
  (`ExactOutputTMPSellBlocked`).
- **Dynamic anti-dump tax**: `_calculateTax(ticksAboveFloor)` ramps linearly
  from `maxDefenseTax` (default 50%, applied at/below the floor) down to
  `baseDefenseTax` (default 0.3%, applied at/above `taxRampTicks = 4080`
  ticks ≈ +50% above floor). Applied by returning a dynamic-fee-flagged value
  from `beforeSwap`. Buys always pay only `baseDefenseTax`.
- **`injectLiquidity(usdcAmount)`** (manager-only): uses `poolManager.unlock`
  + `IUnlockCallback.unlockCallback` + `INCREASE_LIQUIDITY` / `SETTLE_PAIR` to
  add the queued USDC and the matching TMP minted by the manager. Tracks
  `protocolLiquidity` for floor-defense math; burns any TMP leftover.
- **`harvestFees()`** (owner-only): `DECREASE_LIQUIDITY` (zero) +
  `TAKE_PAIR` to collect fees, sends USDC fees to the company, burns TMP fees.
  Carefully subtracts `pendingLiquidityUsdc` from the USDC balance so it
  doesn't sweep liquidity that hasn't been injected yet.
- **`quoteSell` / `quoteBuy`**: view helpers for the frontend; mirror the
  swap math (`FullMath`, `FixedPoint96`) to preview effective output, burn,
  and tax.

#### [`AbstractMoonpotRound.sol`](AbstractMoonpotRound.sol)

Shared base for round contracts. Holds `roundId`, `manager`, `usdc`, immutable
`PRICE / TOTAL_TOKENS / TOTAL_NFTS` and the three share components (validated
to sum exactly to `PRICE`). Tracks lifecycle state (`startTime`, `endTime`,
`tokensSold`, `nftsMinted`, `rewardPool`, `seed`, `seedRequestId`,
`scannedCount`) and exposes `notify*` / `set*` / `start` / `end` /
`depositFunds` / `releaseReward`, all `onlyManager`.

`valueOf(tokenId)` computes `permute(tokenId % TOTAL_TOKENS, seed)` and looks
up the resulting permutation index in the subclass's reward table.

#### [`MoonpotRound1.sol`](MoonpotRound1.sol) … [`MoonpotRound5.sol`](MoonpotRound5.sol) (rounds 6–28 to follow)

Concrete rounds. Each provides the constants for that round and a
`getNFTClass(uint32 draw)` that maps a permutation index to a
`(Class, usdcValue)` pair (16 reward tiers, scaled by round size). All
production rounds share the same 16-tier shape, scaling linearly with the
round's reward pool, sourced from a 17-bit permutation domain via
`TEAPermuter.permute17`.

Currently committed (rounds 1–5):

| Round | Price (USDC) | Tokens    | NFTs   | Reward pool | Max reward |
| ----- | ------------ | --------- | ------ | ----------- | ---------- |
| 1     | $1.15        | 1,000,000 | 99,991 | $1,000,000  | $100,000   |
| 2     | $1.15        | 2,000,000 | 99,991 | $2,000,000  | $200,000   |
| 3     | $1.15        | 3,000,000 | 99,991 | $3,000,000  | $300,000   |
| 4     | $1.15        | 4,000,000 | 99,991 | $4,000,000  | $400,000   |
| 5     | $1.15        | 5,000,000 | 99,991 | $5,000,000  | $500,000   |

Planned price schedule across all 28 rounds (`MAX_ROUNDS = 28`):

| Rounds | Price (USDC)        | Notes                                        |
| ------ | ------------------- | -------------------------------------------- |
| 1–9    | $1.15               | Flat introductory price                      |
| 10–19  | $1.20               | Single step-up                               |
| 20–28  | $1.30 → $2.10       | +$0.10 per round (round 20=$1.30, 28=$2.10)  |

The community share floats to `PRICE − $0.15` (company + liquidity stay flat
at $0.10 + $0.05), so per-token reward-pool funding scales with price as the
sale progresses.

#### [`IMoonpotHook.sol`](IMoonpotHook.sol) / [`IMoonpotManager.sol`](IMoonpotManager.sol) / [`IMoonpotRound.sol`](IMoonpotRound.sol)

Interfaces consumed across the system.

### Library

#### [`lib/TEAPermuter.sol`](lib/TEAPermuter.sol)

Format-preserving permutation built from a TEA-style Feistel cipher. Provides
`permute9 / permute10 / permute14 / permute17 / permute20` (block sizes from
512 to ~1M states) using cycle-walking to map onto an arbitrary `n`. Used by
each round to turn a sequential token index into a deterministic, uniformly
distributed reward-table position from the round seed, so reward allocation is
verifiable post-reveal without any per-token storage.

## Lifecycle

```
                           ┌── setRound(1..N) ──────┐
deploy ─▶ setManager(...) ─┤                        │
(token, NFT, manager)      │                        ▼
                           └── manager.init(...) ─▶ pool live, hook armed
                                                    │
                                                    ▼
                              manager.start() ───▶ round N active
                                                    │
                       buyFor → VRF → processBuy ──┤  (mint TMP + allocate NFTs)
                                                    │
                                  every 2.5% sold ──┤  injectLiquidity()
                                                    │
                                  fully sold out ───┤  round.end() + VRF
                                                    │  (round seed)
                                                    ▼
                                            valueOf(tokenId) computable
                                                    │
                                          claimNFT / claimNFTs ──▶ USDC
                                                    │
                              manager.start() ──────┴──▶ round N+1 …
```

## Dependencies

- `@openzeppelin/contracts`: `ERC20`, `Ownable2Step`, `SafeERC20`, `ReentrancyGuard`, `Math`, `IERC20Permit`
- `erc721a`: `ERC721A`, `ERC721AQueryable`
- `@chainlink/contracts`: `VRFConsumerBaseV2Plus`, `VRFV2PlusClient`
- `@uniswap/v4-core`: `IPoolManager`, `IHooks`, `PoolKey`, `Currency`, `TickMath`, `LPFeeLibrary`, `StateLibrary`, `FullMath`, `FixedPoint96`, `BeforeSwapDelta`
- `@uniswap/v4-periphery`: `IPositionManager`, `IPoolInitializer_v4`, `Actions`, `LiquidityAmounts`
- `@uniswap/v4-hooks-public`: `BaseHook`
- `@uniswap/permit2`: `IPermit2`

Solidity: `^0.8.28`.
