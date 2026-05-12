# Audit Scope

This document defines the scope, trust assumptions, privileged actors, and known limitations for The Moonpot smart-contract system. Read alongside [README.md](README.md) (system architecture) and the contract sources in [`contracts/`](contracts/).

## In scope

All Solidity sources under [`contracts/`](contracts/) **excluding** [`contracts/mocks/`](contracts/mocks/):

| File                                                                                                                                                                                       | Purpose                                                                                                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------- |
| [`contracts/MoonpotManager.sol`](contracts/MoonpotManager.sol)                                                                                                                             | System orchestrator: init, round wiring, `buyFor`, `processBuy`, claim, VRF callbacks, liquidity injection |
| [`contracts/MoonpotHook.sol`](contracts/MoonpotHook.sol)                                                                                                                                   | Uniswap v4 hook: price-floor TMP burn, dynamic anti-dump tax, LP injection callback, fee harvest           |
| [`contracts/MoonpotToken.sol`](contracts/MoonpotToken.sol)                                                                                                                                 | TMP ERC20                                                                                                  |
| [`contracts/MoonpotNFT.sol`](contracts/MoonpotNFT.sol)                                                                                                                                     | TMPNFT ERC721A                                                                                             |
| [`contracts/AbstractMoonpotRound.sol`](contracts/AbstractMoonpotRound.sol)                                                                                                                 | Base round contract: lifecycle, reward pool, manager-only state changes                                    |
| [`contracts/MoonpotRound1.sol`](contracts/MoonpotRound1.sol) … [`contracts/MoonpotRound5.sol`](contracts/MoonpotRound5.sol)                                                                | Per-round constants and 16-tier reward tables                                                              |
| [`contracts/lib/TEAPermuter.sol`](contracts/lib/TEAPermuter.sol)                                                                                                                           | Format-preserving permutation library (Feistel construction)                                               |
| [`contracts/IMoonpotHook.sol`](contracts/IMoonpotHook.sol), [`contracts/IMoonpotManager.sol`](contracts/IMoonpotManager.sol), [`contracts/IMoonpotRound.sol`](contracts/IMoonpotRound.sol) | Interfaces                                                                                                 |

Solidity version: `^0.8.28`. Compiled with `viaIR: true`, `optimizer.runs = 200`, `bytecodeHash: none`.

## Out of scope

- [`contracts/mocks/`](contracts/mocks/): only used by the Foundry test suite, never deployed.
- [`lib/v4-hooks-public/`](lib/v4-hooks-public/): vendored Uniswap v4 sources (PoolManager, PositionManager, Permit2, etc.) and forge-std. These are third-party dependencies considered trusted (see [Trust assumptions](#trust-assumptions)).
- [`node_modules/`](node_modules/): npm-vendored libraries (`@openzeppelin/contracts`, `@chainlink/contracts`, `erc721a`). Trusted.
- [`ignition/`](ignition/) and [`scripts/`](scripts/): deployment / one-shot helper code.

## Trust assumptions

External components the protocol depends on, treated as honest and correctly implemented:

- **Chainlink VRF v2.5**: `vrfCoordinator` returns uniform random uint256 words for each `requestRandomWords` call. The protocol's safety depends on VRF being non-manipulable.
- **Uniswap v4**: `PoolManager`, `PositionManager`, `Permit2`. The protocol delegates pool lifecycle, LP minting, and ERC20 allowance flows to these contracts. The hook is registered with the `PoolManager` via the v4 hook-permission address bits.
- **OpenZeppelin v5**: `ERC20`, `Ownable2Step`, `SafeERC20`, `ReentrancyGuard`, `Math`, `IERC20Permit`.
- **erc721a**: `ERC721A`, `ERC721AQueryable`.
- **USDC** (Base mainnet `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`): standard ERC20 plus EIP-2612 `permit`. The Manager's `buyFor` wraps the `permit` call in `try/catch`, so it functions even if `permit` reverts or is not implemented.

## Privileged actors

### Manager owner (`MoonpotManager.owner()`)

The deployer of `MoonpotManager` is its owner via Chainlink's `ConfirmedOwnerWithProposal` (two-step transfer). Can:

| Function                                                                         | Effect                                                                                                                                                             |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `init(usdcAmount, ceilingTick)`                                                  | One-shot. Opens the initial LP position and arms the hook. Reverts after first successful call.                                                                    |
| `start()`                                                                        | Starts round 1, or advances to the next round once the current one has ended (manual rollover; the natural rollover happens via `_maybeEndRound` inside `buyFor`). |
| `setRound(id, addr)`                                                             | Wires a round contract into slot `id` (1..28). One-shot per `id`.                                                                                                  |
| `setCompany(newCompany)`                                                         | Updates the company-share recipient. Reverts on zero.                                                                                                              |
| `setVRFParams(keyHash, subId, callbackGasLimit)`                                 | Updates VRF request parameters.                                                                                                                                    |
| `retryRoundReveal(roundId)`                                                      | Re-requests a VRF word for a stuck round seed (round must be ended and not yet seeded).                                                                            |
| `reDrawPurchase(purchaseId)` (owner immediate, anyone after `VRF_TIMEOUT = 24h`) | Re-requests a VRF word for a stuck purchase draw.                                                                                                                  |

The owner cannot withdraw funds, mint TMP / TMPNFT, override claims, modify reward tables, or change deployed round contracts.

### Hook owner (`MoonpotHook.owner()`)

Set by constructor (currently the deployer). OZ `Ownable`. Can:

| Function                                    | Effect                                                                                                                                        |
| ------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `setManager(addr)`                          | One-shot; sets the trusted manager that may call `setPositionId` / `setCurrentFloorTick` / `injectLiquidity`. Reverts on zero or second call. |
| `setDefenseParams(base, max, taxRampTicks)` | Adjusts dynamic-tax bounds. Reverts if `base > max`, `taxRampTicks <= 0`, or `max > 1_000_000` (1e6 = 100%).                                  |
| `harvestFees()`                             | Pulls accrued LP fees: USDC fees minus `pendingLiquidityUsdc` go to `_company`; TMP fees are burned.                                          |

The hook owner cannot disable the floor-defense burn, lift the `ExactOutputTMPSellBlocked` guard, or change which token is treated as TMP/USDC (immutable).

### Token / NFT owners

`MoonpotToken.owner()` and `MoonpotNFT.owner()` are OZ `Ownable2Step` (two-step transfer). Each can call **only** `setManager(addr)` once. After that, only the manager can mint. `MoonpotNFT.owner()` additionally can rotate `baseURI` until `freezeBaseURI()` is called (one-way).

### Manager-only callers (not human owners)

Several functions on the Hook and Round contracts have an `onlyManager` modifier: they can only be called by the `MoonpotManager` contract itself, not by an EOA. These are: `Hook.setPositionId / setCurrentFloorTick / injectLiquidity`, all `AbstractMoonpotRound` state-mutating functions (`start / end / notify* / setSeed* / depositFunds / releaseReward`), and `Token.mint` / `NFT.mintTo`.

## Known limitations

- **`MoonpotRound2..5` are only smoke-tested.** They share the exact same 16-tier shape as `MoonpotRound1` (which has 100% test coverage); the smoke tests verify the top and bottom tiers and the constructor args.
- **`MoonpotHook` test coverage: 83% lines, 94% functions.** The off-fork suite uses a mocked v4 setup; pool-state-dependent paths (`beforeSwap` floor defense + tax ramp, `injectLiquidity` via the `unlock` callback, `harvestFees`) are covered by Base-mainnet fork tests in [`test/fork/`](test/fork/), exercised against the real Uniswap v4 PoolManager, PositionManager, and Permit2. The remaining uncovered lines are mostly defensive `if`-branches (`liquidityToAdd == 0` no-op, `tmpFees == 0` early return) and a small amount of unused error-path code.
- **Rounds 6–28 are not yet committed.** The Manager hardcodes `MAX_ROUNDS = 28` and the planned price schedule is documented in the README (rounds 1–9: $1.15, 10–19: $1.20, 20–28: $1.30 → $2.10 by $0.10/round). The round contracts for 6–28 will follow the same shape as Rounds 1–5.
- **Reward pool sufficiency.** The Manager's claim flow calls `round.releaseReward(recipient, value)`, which reverts on `InsufficientFunds` if `rewardPool < value`. The reward pool is fed only by the per-token community share. If a round is not fully sold out, large-tier claims can outstrip the pool. There is no mechanism in the manager to top up a round's pool: that depends on the round selling out (or off-chain action).
- **VRF dependency.** If Chainlink VRF stops responding, purchases get stuck in `isDrawn = false` and rounds cannot be seeded. The recovery paths are `reDrawPurchase` (anyone after 24h, owner immediate) and `retryRoundReveal` (owner only). There is no fallback randomness source.
- **The hook's `_company` reads from `IMoonpotManager.company()` at fee-harvest time.** Changing `setCompany` on the manager immediately redirects future LP fees to the new recipient (see `MoonpotHook.harvestFees`).
- **TEA permutation rounds = 4.** All round contracts call `TEAPermuter.permute17(..., seed, 4)`. Four Feistel rounds is below the textbook recommendation of 6+ for cryptographic uses, but the permutation is not used for confidentiality: only for uniform reward distribution from a public seed. Verify that 4 rounds yield acceptable distribution properties for the use case.

## Deployment topology

Production deployment is on **Base mainnet** with parameters in [`ignition/parameters/mainnet.json`](ignition/parameters/mainnet.json). The deployment order is:

1. **Pre-deployed externally:** USDC (Circle), `PoolManager` (Uniswap v4), `PositionManager` (Uniswap v4), `Permit2` (Uniswap).
2. **`TMPOnlySystem`**: deploys `MoonpotToken`.
3. **Hook salt mining** ([`scripts/mine-hook-salt.ts`](scripts/mine-hook-salt.ts)): finds a CREATE2 salt so the hook address has the v4 hook-flag bits (`BEFORE_INITIALIZE | BEFORE_SWAP | BEFORE_SWAP_RETURNS_DELTA`).
4. **`HookOnlySystem`**: deploys `MoonpotHook` at the mined address.
5. **`MoonpotSystem`**: deploys `MoonpotNFT`, `MoonpotManager`, `MoonpotRound1..5`; wires `setManager` on TMP / NFT / Hook; calls `setRound(1..5)`; transfers $1M USDC to the manager; calls `init` and `start`.

Live mainnet addresses (post-deploy) are in [`ignition/parameters/mainnet.json`](ignition/parameters/mainnet.json).

## Out-of-scope security boundaries

- **Off-chain components** (API, frontend, signer keystore generation) are not in audit scope.
- **The deployer EOA / multisig** holding the owner keys is the trust root; key management is out of scope.
- **Chainlink subscription funding** for VRF is operational, not in scope.
- **Network-level censorship / front-running** of `buyFor` purchases is acknowledged but not mitigated at the contract level.

## Test suite

187 Foundry tests covering the Manager + Round + Abstract + Token + NFT + TEAPermuter surfaces. See the [README test layout section](README.md#test-layout) for per-file scope. Run with:

```sh
forge test
```

Coverage; Manager / Round / Token / NFT / TEAPermuter ≥ 84% lines, Hook 83%.
