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

#### [`MoonpotToken.sol`](contracts/MoonpotToken.sol): `TMP`

ERC20 (`"The Moonpot Token"`, `TMP`) with `Ownable2Step`. Only the
one-time-set `manager` (the `MoonpotManager`) can `mint`. Anyone holding TMP
can `burn` their own balance.

#### [`MoonpotNFT.sol`](contracts/MoonpotNFT.sol): `TMPNFT`

ERC721A (`"The Moonpot NFT"`, `TMPNFT`) with `ERC721AQueryable` and
`Ownable2Step`. Only the manager can `mintTo`. The round ID is stamped into
the ERC721A `extraData` on the first token of each batch and read back via
`getRound(tokenId)` to look up the reward table at redemption time. The base URI can
be rotated by the owner (emits `BatchMetadataUpdate`) until `freezeBaseURI()`
is called.

#### [`MoonpotManager.sol`](contracts/MoonpotManager.sol)

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

#### [`MoonpotHook.sol`](contracts/MoonpotHook.sol)

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

#### [`AbstractMoonpotRound.sol`](contracts/AbstractMoonpotRound.sol)

Shared base for round contracts. Holds `roundId`, `manager`, `usdc`, immutable
`PRICE / TOTAL_TOKENS / TOTAL_NFTS` and the three share components (validated
to sum exactly to `PRICE`). Tracks lifecycle state (`startTime`, `endTime`,
`tokensSold`, `nftsMinted`, `rewardPool`, `seed`, `seedRequestId`,
`scannedCount`) and exposes `notify*` / `set*` / `start` / `end` /
`depositFunds` / `releaseReward`, all `onlyManager`.

`valueOf(tokenId)` computes `permute(tokenId % TOTAL_TOKENS, seed)` and looks
up the resulting permutation index in the subclass's reward table.

#### [`MoonpotRound1.sol`](contracts/MoonpotRound1.sol) … [`MoonpotRound5.sol`](contracts/MoonpotRound5.sol) (rounds 6–28 to follow)

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

#### [`IMoonpotHook.sol`](contracts/IMoonpotHook.sol) / [`IMoonpotManager.sol`](contracts/IMoonpotManager.sol) / [`IMoonpotRound.sol`](contracts/IMoonpotRound.sol)

Interfaces consumed across the system.

### Library

#### [`contracts/lib/TEAPermuter.sol`](contracts/lib/TEAPermuter.sol)

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

## Development

The repo ships a dual Hardhat 4 + Foundry toolchain so the same Solidity sources can be compiled, tested, and deployed by either runner. Foundry is used for the unit test suite; Hardhat 4 + Ignition is used for deployments.

### Prerequisites

- **Node.js** ≥ 20 ([install](https://nodejs.org/))
- **pnpm** ≥ 9 (`npm install -g pnpm`)
- **Foundry** (`forge`, `cast`, `anvil`) ([install](https://book.getfoundry.sh/getting-started/installation))

### Install

```sh
pnpm install        # JS deps + Foundry-side npm packages (@openzeppelin, @chainlink, erc721a)
```

The `lib/v4-hooks-public/` submodule contents are committed in-tree (no `git submodule init` required).

### Build

```sh
forge build         # Foundry build → `out/`
pnpm hardhat build  # Hardhat 4 build → `artifacts/`
```

Both runners share the same `solc 0.8.28` profile with `viaIR: true`, optimizer enabled (200 runs), and `bytecodeHash: none`.

### Test

The test suite is Foundry-based (`test/*.t.sol` + `test/fork/*.fork.t.sol`) and ships with **198 tests** covering every Moonpot contract, including the v4-pool-state-dependent paths in `MoonpotHook` via Base-mainnet fork tests.

```sh
forge test                                                  # full suite (unit + fork)
forge test --no-match-path "test/fork/*"                    # unit tests only (no network)
forge test --match-path test/MoonpotManager.buyFor.t.sol    # single file
forge test --match-test testBuyForHappyPath -vvv            # single test, verbose
forge test --gas-report                                     # gas snapshots
```

Fork tests under [`test/fork/`](test/fork/) use the public Base RPC by default. Override with an environment variable for higher throughput or a paid provider:

```sh
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/<key> forge test
BASE_FORK_BLOCK=33000000 forge test --match-path "test/fork/*"
```

If no network is available the fork-test `setUp()` calls `vm.skip(true)`, so the rest of the suite still passes.

Coverage:

```sh
forge coverage --ir-minimum --report summary
```

### Test layout

```
test/
├── Fixtures.sol                              # abstract BaseFixture + InitializedFixture
├── mocks/
│   └── MockPermit2.sol                       # minimal Permit2 stub for unit tests
├── MockUSDT.t.sol                            # pre-existing
├── MoonpotToken.t.sol                        # pre-existing
├── MoonpotNFT.t.sol                          # pre-existing
├── TEAPermuter.t.sol                         # pre-existing (permutation bijection proofs)
├── MoonpotRound1.t.sol                       # reward-tier table, valueOf, constructor reverts
├── AbstractMoonpotRound.t.sol                # lifecycle, notify*, releaseReward, onlyManager
├── MoonpotManager.access.t.sol               # admin setters + reverts (no v4 needed)
├── MoonpotHook.setters.t.sol                 # setDefenseParams bounds, setManager one-shot
├── MoonpotHook.quotes.t.sol                  # _calculateTax + _computeMaxTmpSell via harness
├── MoonpotManager.init.t.sol                 # init happy + 4 reverts
├── MoonpotManager.buyFor.t.sol               # happy + 6 reverts, share routing, VRF request
├── MoonpotManager.vrf.t.sol                  # fulfillRandomWords dispatch
├── MoonpotManager.processBuy.t.sol           # Bernoulli NFT allocation
├── MoonpotManager.reDraw.t.sol               # VRF re-request (timeout + owner)
├── MoonpotManager.claim.t.sol                # single + batched + 4 reverts
├── MoonpotManager.liquidityInjection.t.sol   # 25k checkpoint crossings
├── MoonpotManager.integration.t.sol          # E2E: init → buy → VRF → process → claim
├── Fixtures.smoke.t.sol                      # fixture wiring sanity
└── fork/                                     # Base-mainnet fork tests (real v4)
    ├── ForkFixture.sol                       # deploys fresh Moonpot system into a Base fork
    ├── ForkRouter.sol                        # minimal v4 swap helper (IUnlockCallback)
    ├── ForkFixture.smoke.fork.t.sol          # fork wiring sanity
    ├── MoonpotHook.beforeSwap.fork.t.sol     # real swaps: buy tax, sell clamp + burn, exact-output revert, tax ramp
    ├── MoonpotHook.injectLiquidity.fork.t.sol # manager-triggered LP injection via real PositionManager
    └── MoonpotHook.harvestFees.fork.t.sol    # fee accrual + harvest, preserves pendingLiquidity
```

The off-fork suite uses a **mocked v4 setup** (stub PoolManager + `vm.mockCall` on `extsload`, mocked PositionManager, MockPermit2). This avoids solc-version conflicts that come with importing v4-periphery (pinned to 0.8.26) and Permit2 (pinned to 0.8.17) directly from 0.8.28 test contracts. The Hook's pool-state-dependent paths (`beforeSwap` floor defense + tax ramp, `injectLiquidity` via `unlock` callback, `harvestFees`) are covered separately in fork mode against the real Uniswap v4 PoolManager, PositionManager, and Permit2 on Base mainnet.

### Deploy

Deployments use **Hardhat Ignition** modules in [`ignition/modules/`](ignition/modules/). Network parameters live in [`ignition/parameters/`](ignition/parameters/).

Set up secrets (encrypted at rest by `hardhat-keystore`):

```sh
pnpm hardhat keystore set BASE_RPC_URL
pnpm hardhat keystore set WALLET_PRIVATE_KEY
pnpm hardhat keystore set ETHERSCAN_API_KEY
```

Or supply them as env vars (see [`.env.example`](.env.example)).

Production flow on Base:

```sh
# 1. Mine the hook salt so its deployed address has the v4 hook-flag bits
pnpm hardhat run scripts/mine-hook-salt.ts

# 2. Deploy the hook at the mined address
pnpm hardhat ignition deploy ignition/modules/HookOnlySystem.ts \
  --network base \
  --parameters ignition/parameters/mainnet.json

# 3. Deploy the rest of the system (manager, NFT, rounds, wire everything)
pnpm hardhat ignition deploy ignition/modules/MoonpotSystem.ts \
  --network base \
  --parameters ignition/parameters/mainnet.json
```

Smaller standalone modules (`TMPOnlySystem`, `MockUSDCOnly`, `MockVRFOnly`) are available for partial / testnet deployments.

### Project layout

```
.
├── contracts/                  # production Solidity sources
│   ├── *.sol                   # Manager, Hook, Token, NFT, AbstractRound, Round1..5
│   ├── lib/TEAPermuter.sol     # Feistel permutation library
│   └── mocks/                  # local test doubles (MockUSDC, MockVRFCoordinator, ...)
├── test/                       # Foundry tests (see above)
├── scripts/                    # operational + diagnostic TS scripts
├── ignition/                   # Hardhat Ignition deploy modules + parameters
├── lib/v4-hooks-public/        # Uniswap v4 + Permit2 sources (vendored submodule)
├── foundry.toml
├── hardhat.config.ts
├── remappings.txt              # shared Foundry remappings
└── .env.example
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
