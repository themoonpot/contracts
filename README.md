# The Moonpot Contracts

Solidity **0.8.33** contracts for The Moonpot: a multi-round token sale that mints **TMP** (ERC20) and **TMPNFT** (ERC721A) per purchase, assigns each TMPNFT a deterministic USDC redemption value via a Chainlink VRF v2.5 round seed, and seeds a Uniswap v4 pool with a custom hook that enforces a price floor and a dynamic anti-dump tax.

- **Toolchain:** Foundry (unit + fork tests) and Hardhat 4 + Ignition (deployments), sharing the same sources via `remappings.txt`.
- **Target chain:** Base mainnet (Uniswap v4 + Permit2 + Circle USDC).
- **Run it locally:** see [Quickstart](#quickstart-run-locally-on-a-base-fork) — the whole system runs on a local Anvil fork of Base, no mainnet deploy required.

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

## Quickstart: run locally on a Base fork

The system is tightly coupled to infrastructure that **only exists on Base
mainnet** — the Uniswap v4 `PoolManager` / `PositionManager` and `Permit2`. A
bare local chain has none of it, so `init` (which creates the real pool) can't
run. The fix is to run against a **local Anvil fork of Base**: a private,
free, local copy of Base's state where those contracts already exist and your
contracts deploy on top. Two pieces are swapped for local-only doubles:

- **USDC → `MockUSDC`** — the deployer is minted 10B, so no whale/storage tricks.
- **VRF → mock coordinator** — Chainlink has no off-chain node on a fork, so you
  call `fulfill(reqId)` yourself to simulate the random-word callback.

Everything else (v4, Permit2) is the real Base code from the fork.

### Prerequisites

- **Foundry** (`forge`, `cast`, `anvil`) — [install](https://book.getfoundry.sh/getting-started/installation)
- A **Base mainnet RPC URL**. Use a paid/archive provider (Alchemy, QuickNode);
  the public `https://mainnet.base.org` rate-limits forking hard.
- `pnpm install` once (pulls the npm-side Solidity deps used by the build).

### One command

```sh
BASE_RPC_URL=https://<your-base-rpc> ./scripts/local-fork.sh
# pin a block for determinism + RPC caching:
BASE_RPC_URL=... BASE_FORK_BLOCK=33000000 ./scripts/local-fork.sh
```

This boots an Anvil fork on `http://127.0.0.1:8545`, deploys the full system
([`scripts/DeployLocal.s.sol`](scripts/DeployLocal.s.sol) — mines + CREATE2-deploys
the hook, deploys + wires everything, runs `init` + `start`), and prints every
deployed address. Anvil keeps running so you can interact with it.

### Drive a full purchase

Copy the addresses the deploy logged into env vars, then run the lifecycle
([`scripts/DriveBuy.s.sol`](scripts/DriveBuy.s.sol) does
`fund buyer → approve → buyFor → vrf.fulfill → processBuy`):

```sh
export MANAGER=0x.. USDC=0x.. VRF=0x.. NFT=0x..
forge script scripts/DriveBuy.s.sol:DriveBuy --rpc-url http://127.0.0.1:8545 --broadcast --slow
```

It prints the NFTs minted and TMP balance for the buyer. Tune the purchase with
`TOKENS=<n>` (default 100).

### Run it by hand (two terminals)

If you'd rather manage Anvil yourself:

```sh
# terminal 1
anvil --fork-url $BASE_RPC_URL            # add --fork-block-number <n> to pin

# terminal 2
forge script scripts/DeployLocal.s.sol:DeployLocal \
  --rpc-url http://127.0.0.1:8545 --broadcast --slow
# ...then DriveBuy as above, or poke individual calls with `cast`.
```

`DeployLocal` reads optional env overrides: `PRIVATE_KEY` (deployer; default
Anvil account[0]), `INITIAL_USDC` (default 100,000e6), `CEILING_TICK` (default
`-245880`, must be tick-spacing aligned), `COMPANY`, `BUYER` + `BUYER_FUND_USDC`.

> **Fork gotcha:** the NFT recipient must be a **codeless EOA on the fork**.
> Anvil's default account `0xf39F…2266` is a *live contract on Base mainnet*, so
> minting an NFT to it triggers `onERC721Received` and reverts `processBuy` with
> empty revert data. `DriveBuy` avoids this by deriving a fresh throwaway buyer
> and funding it from the deployer — if you drive buys by hand, use a fresh
> address as the buyer, not the default account. (Deploying *from* account[0] is
> fine; only NFT receipt breaks.)

To claim rewards you also need the round ended + seeded (a separate round-level
VRF reveal); see the [Lifecycle](#lifecycle) section.

## Contracts

### Core

#### [`MoonpotToken.sol`](contracts/MoonpotToken.sol): `TMP`

ERC20 (`"The Moonpot Token"`, `TMP`) with `Ownable2Step`. Only the
one-time-set `manager` (the `MoonpotManager`) can `mint`. Anyone holding TMP
can `burn` their own balance.

#### [`MoonpotNFT.sol`](contracts/MoonpotNFT.sol): `TMPNFT`

ERC721A (`"The Moonpot NFT"`, `TMPNFT`) with `ERC721AQueryable` and
`Ownable2Step`. Only the manager can `mintTo`. The round ID is stamped into
the ERC721A `extraData` on the first token of each batch (and preserved across
transfers, cleared on burn) and read back via `getRound(tokenId)` to look up
the reward table at redemption time. The base URI can be rotated by the owner
(emits `BatchMetadataUpdate`) until `freezeBaseURI()` is called (emits
`BaseURILocked`).

#### [`MoonpotManager.sol`](contracts/MoonpotManager.sol)

Single source of truth. Owns the lifecycle of up to `MAX_ROUNDS = 28` rounds.

- **`init(usdcAmount, ceilingTick)`**: one-shot. Validates `ceilingTick` is
  tick-spacing aligned, mints the initial TMP, builds the Uniswap v4 `PoolKey`,
  opens a wide LP position via `permit2` + `IPositionManager.multicall`
  (bundles `initializePool` + `MINT_POSITION` + `SETTLE_PAIR`), burns leftover
  TMP, and registers the position with the hook (`setPosition`). Initial sqrt
  price is set `INIT_TICK_PREMIUM = 1200` ticks above the round-1 floor.
- **`setRound(id, addr)`**: wires round contracts in (one-shot per id; checks
  the round's own `roundId` matches).
- **`start()`**: starts round 1, or rolls forward to the next round once the
  current one has ended. Updates the hook's `currentFloorTick` to the new
  round's price.
- **`buyFor(buyer, usdcAmount, deadline, v, r, s)`**: entry point for
  purchases. Pulls USDC (with a best-effort `permit` only if allowance is
  insufficient), routes shares, mints `tokens * 1e18` TMP to the buyer,
  requests a VRF word for the purchase's NFT allocation, and emits
  `PurchaseCommitted`. Capped at `MAX_PURCHASE_LIMIT = 10_000` tokens per call.
  Calls `_maybeInjectLiquidity` (every 2.5% of supply) and `_maybeEndRound`
  (when the round sells out).
- **`processBuy(purchaseId)`**: once VRF has filled the purchase seed
  (`isDrawn`), allocates NFTs by walking `tmpAmount` Bernoulli trials against
  the **live** remaining ratio `nftsLeft / drawsLeft` (read fresh, never a
  buy-time snapshot, so total mints are capped at `TOTAL_NFTS` regardless of
  buy/process ordering). Mints the resulting count of TMPNFTs and notifies the
  round.
- **`claimNFT(tokenId)` / `claimNFTs(tokenIds[])`**: after a round has ended
  AND been seeded by VRF, NFT holders compute their token's USDC value via
  the round's `valueOf(tokenId)` (deterministic from the round seed) and
  `releaseReward` USDC out of the round's pool. `claimNFTs` batches by round.
- **`reDrawPurchase(purchaseId)`**: anyone can re-request a stuck purchase
  VRF allocation after `VRF_TIMEOUT = 24h`; the owner can re-request immediately.
- **`retryRoundReveal(roundId)`**: owner-only re-request of the round seed
  (clears the superseded VRF routing so a never-fulfilled request can't linger).
- **VRF callbacks**: `fulfillRandomWords` dispatches by `VRFRequestType`
  (`Purchase` → set purchase seed; `Round` → set round seed, ignoring duplicates).

#### [`MoonpotHook.sol`](contracts/MoonpotHook.sol)

Uniswap v4 hook (`BaseHook`, `Ownable2Step`) attached to the TMP/USDC pool.
Implements `beforeInitialize` and `beforeSwap` (with delta + dynamic fee).

- **Price-floor defense**: on every TMP→USDC swap, the hook reads the current
  tick, clamps the user's sell to a `_computeMaxTmpSell` amount that would not
  push price below the round's `floorTickLower/Upper`, and **burns the
  excess TMP** (taken via `poolManager.take` and burned through
  `MoonpotToken.burn`). At/below the floor `maxTmpSell` is 0, so the whole sell
  is burned — the hard floor wall. Exact-output TMP sells are blocked
  (`ExactOutputTMPSellBlocked`). The floor tick is validated to stay within
  `TickMath` range so the swap path can't be bricked.
- **Dynamic anti-dump tax**: `_calculateTax(ticksAboveFloor)` ramps linearly
  from `maxDefenseTax` (default 50%, applied at/below the floor) down to
  `baseDefenseTax` (default 0.3%, applied at/above `taxRampTicks = 4080`
  ticks ≈ +50% above floor), and is applied by returning a dynamic-fee-flagged
  value from `beforeSwap`. Buys always pay only `baseDefenseTax`. The owner can
  retune within a hard `MAX_DEFENSE_TAX = 90%` cap (so an exit always exists).
- **Sandwich-guarded liquidity injection** (manager-only `injectLiquidity`):
  uses `poolManager.unlock` + `IUnlockCallback.unlockCallback` +
  `INCREASE_LIQUIDITY` / `SETTLE_PAIR` to add the queued USDC + matching TMP.
  A TWAP oracle (a ported Uniswap v3 ring buffer) plus a floor-band fallback
  gate injection via `injectionAllowed()`; if the live price deviates from the
  reference, the manager **defers** (leaves the USDC queued, retries next buy)
  rather than minting at a manipulated price. Tracks `protocolLiquidity` for
  floor-defense math; burns any TMP leftover.
- **`harvestFees()`** (owner-only): `DECREASE_LIQUIDITY` (zero) + `TAKE_PAIR`
  to collect fees, sends USDC fees to the company, burns TMP fees. Subtracts
  `pendingLiquidityUsdc` so it doesn't sweep liquidity not yet injected.
- **`quoteSell` / `quoteBuy`**: view helpers for the frontend; mirror the
  swap math (`FullMath`, `FixedPoint96`) to preview effective output, burn,
  and tax.

#### [`AbstractMoonpotRound.sol`](contracts/AbstractMoonpotRound.sol)

Shared base for round contracts. Holds `roundId`, `manager`, `usdc`, immutable
`PRICE / TOTAL_TOKENS / TOTAL_NFTS` and the three share components (validated
to sum exactly to `PRICE`). Tracks lifecycle state (`startTime`, `endTime`,
`tokensSold`, `nftsMinted`, `rewardPool`, `seed`, `seedRequestId`,
`scannedCount`) and exposes `notify*` / `set*` / `start` / `end` /
`depositFunds` / `releaseReward`, all `onlyManager`, with lifecycle guards
(can't double-start/end/seed). NFT counts are `uint256` throughout.

`valueOf(tokenId)` computes `permute(tokenId % TOTAL_TOKENS, seed)` and looks
up the resulting permutation index in the subclass's reward table (called
internally, no external self-calls).

#### [`MoonpotRound1.sol`](contracts/MoonpotRound1.sol) … [`MoonpotRound5.sol`](contracts/MoonpotRound5.sol) (rounds 6–28 to follow)

Concrete rounds. Each provides the constants for that round and a
`getNFTClass(uint32 draw)` that maps a permutation index to a
`(Class, usdcValue)` pair (16 reward tiers, scaled by round size). All
production rounds share the same 16-tier shape, scaling linearly with the
round's reward pool, sourced from a 17-bit permutation domain via
`TEAPermuter.permute17` (6 Feistel rounds).

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

#### [`contracts/lib/Oracle.sol`](contracts/lib/Oracle.sol)

A faithful 0.8.x port of Uniswap v3-core's audited `Oracle` ring buffer
(BUSL-1.1, kept as-is with attribution). Backs the hook's TWAP sandwich guard
for liquidity injection.

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
                                  every 2.5% sold ──┤  injectLiquidity() (guarded)
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

The repo ships a dual Hardhat 4 + Foundry toolchain so the same Solidity
sources can be compiled, tested, and deployed by either runner. Both pin
**`solc 0.8.33`** with `viaIR: true`, optimizer enabled (200 runs), and
`bytecodeHash: none`.

### Prerequisites

- **Node.js** ≥ 20 ([install](https://nodejs.org/))
- **pnpm** ≥ 9 (`npm install -g pnpm`)
- **Foundry** (`forge`, `cast`, `anvil`) ([install](https://book.getfoundry.sh/getting-started/installation))

### Install

```sh
pnpm install        # JS deps + Foundry-side npm packages (@openzeppelin, @chainlink, erc721a)
```

The `lib/v4-hooks-public/` submodule contents are committed in-tree (no
`git submodule init` required).

### Build

```sh
forge build         # Foundry build → out/
pnpm hardhat build  # Hardhat 4 build → artifacts/
```

### Test

The test suite is Foundry-based: **217 unit tests** (`test/*.t.sol`) plus
**11 Base-mainnet fork tests** (`test/fork/*.fork.t.sol`) covering the
v4-pool-state-dependent paths in `MoonpotHook`.

```sh
forge test --no-match-path "test/fork/*"                    # unit tests only (no network)
forge test                                                  # full suite (needs a Base RPC for fork tests)
forge test --match-path test/MoonpotManager.buyFor.t.sol    # single file
forge test --match-test testBuyForHappyPath -vvv            # single test, verbose
forge test --gas-report                                     # gas snapshots
```

Fork tests use the public Base RPC by default. Override for higher throughput
or a pinned block:

```sh
BASE_RPC_URL=https://base-mainnet.g.alchemy.com/v2/<key> forge test --match-path "test/fork/*"
BASE_FORK_BLOCK=33000000 forge test --match-path "test/fork/*"
```

If no network is available the fork-test `setUp()` calls `vm.skip(true)`, so
the rest of the suite still passes.

Coverage:

```sh
forge coverage --ir-minimum --report summary
```

The off-fork suite uses a **mocked v4 setup** (stub PoolManager + `vm.mockCall`
on `extsload`, mocked PositionManager, `MockPermit2`) so unit tests need no
network. The Hook's pool-state-dependent paths (`beforeSwap` floor defense +
tax ramp, `injectLiquidity` via `unlock` callback, `harvestFees`) are covered
in fork mode against the real Uniswap v4 PoolManager, PositionManager, and
Permit2 on Base.

### Deploy (Base mainnet)

Production deployments use **Hardhat Ignition** modules in
[`ignition/modules/`](ignition/modules/); network parameters live in
[`ignition/parameters/`](ignition/parameters/).

Set up secrets (encrypted at rest by `hardhat-keystore`), or supply them as env
vars (see [`.env.example`](.env.example)):

```sh
pnpm hardhat keystore set BASE_RPC_URL
pnpm hardhat keystore set WALLET_PRIVATE_KEY
pnpm hardhat keystore set ETHERSCAN_API_KEY
```

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

`scripts/calculate-ceiling-tick.ts` helps compute the `positionTickUpper`
parameter. Smaller standalone modules (`TMPOnlySystem`, `MockUSDCOnly`,
`MockVRFOnly`) are available for partial / testnet deployments.

> For **local** testing, don't use the Ignition mainnet flow — use the
> Foundry fork scripts in the [Quickstart](#quickstart-run-locally-on-a-base-fork).

### Project layout

```
.
├── contracts/                  # production Solidity sources
│   ├── *.sol                   # Manager, Hook, Token, NFT, AbstractRound, Round1..5
│   ├── lib/                     # TEAPermuter (Feistel) + Oracle (v3 TWAP port)
│   └── mocks/                  # local test doubles (MockUSDC, MockVRFCoordinator, ...)
├── test/                       # Foundry tests (unit + fork/)
├── scripts/                    # Foundry scripts (DeployLocal, DriveBuy, local-fork.sh) + TS helpers (mine-hook-salt, calculate-ceiling-tick)
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
- `@uniswap/v4-periphery`: `IPositionManager`, `IPoolInitializer_v4`, `Actions`, `LiquidityAmounts`, `HookMiner`
- `@uniswap/v4-hooks-public`: `BaseHook`
- `@uniswap/permit2`: `IPermit2`

Solidity: `0.8.33` (pinned).
