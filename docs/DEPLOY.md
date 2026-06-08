# Deploy runbook — Moonpot on Base

One Foundry script — [`scripts/DeployBase.s.sol`](../scripts/DeployBase.s.sol) —
deploys the **full 28-round system** to Base mainnet in a **single command**. It
mines the v4 hook salt in-script (`HookMiner`), deploys + wires every contract,
seeds the pool, opens round 1, and (optionally) hands all ownership to a Safe
multisig. No offline mining, no config edits, no params files.

- **`MOCK=true`** → `MockUSDC` + the de-branded `Mock*` contracts (a safe,
  clearly-distinct copy for end-to-end testing).
- **`MOCK=false`** (default) → the real `Moonpot*` contracts against live Circle USDC.
- **`SAFE=0x…`** → after setup, ownership of every contract is transferred to the
  Safe (the EOA keeps no control).

Both use real Chainlink VRF. Plan: **deploy mock → validate → deploy production.**

| | Mock | Production |
|---|---|---|
| `MOCK` | `true` | unset |
| payment token | deploys `MockUSDC` (mints 10B to deployer) | real USDC — deployer must hold `INITIAL_USDC` |
| contracts | `Mock*` (distinct names) | real `Moonpot*` |
| ownership | EOA (or a test Safe) | **Safe multisig** (`SAFE=…`) |
| off-chain | `NETWORK=mock`, `…-relayer-mock`, `*_mock` monitors | `NETWORK=mainnet`, `…-relayer-prod`, prod monitors |

---

## Prerequisites

- A **deployer EOA** in the Foundry keystore, funded with **ETH on Base** for gas:
  ```bash
  cast wallet new                                      # note address + key
  cast wallet import moonpot-deployer --interactive    # paste key, set password
  ```
  (Or pass `PRIVATE_KEY=0x…` instead of `--account`.) With a Safe, this EOA is a
  throwaway — it only needs gas + the seed and ends up with no control.
- `BASE_RPC_URL` exported; `ETHERSCAN_API_KEY` for `--verify`.
- `VRF_SUB_ID` — your Chainlink VRF v2.5 subscription id (**required**).
- **Production:** the deployer must already hold `INITIAL_USDC` (default **1,000**)
  of **real USDC** (it's transferred as the LP seed), and a deployed **Safe**.
- Deploy from the `mock-deploy-mode` branch (it carries the `Mock*` contracts, all
  28 round contracts, the `"The Moonpot"` token name, and `DeployBase`).

### Tunables (env)
| var | default | notes |
|---|---|---|
| `MOCK` | `false` | `true` = mock system |
| `SAFE` | none | multisig to receive ownership of all contracts |
| `VRF_SUB_ID` | — | **required** |
| `INITIAL_USDC` | `1000e6` | LP seed (base units) |
| `CEILING_TICK` | `-245880` | LP ceiling ($2.10×10=$21). Sign depends on token ordering: **-245880** if `usdcIsToken0=false`, **245820** if `true`. The script **reverts on a wrong sign**, so dry-run first to learn the ordering. |
| `COMPANY` | `SAFE` if set, else deployer | fee recipient |
| `VRF_COORDINATOR` / `VRF_KEY_HASH` | Base defaults | real Chainlink VRF |
| `PRIVATE_KEY` | — | alternative to `--account` |

---

## Dry run first (always)

Run the **exact** command **without `--broadcast`** to simulate the whole deploy
against forked Base state — it deploys all 28 rounds, mines the hook, runs `init`
(creating the v4 pool), `start`, and the Safe handoff, then reports addresses + gas.

```bash
# against a local Base-fork anvil, or directly: --rpc-url "$BASE_RPC_URL"
MOCK=true VRF_SUB_ID=1 forge script scripts/DeployBase.s.sol:DeployBase \
  --rpc-url http://127.0.0.1:8545 --sender <deployer-address>
```

Read **`usdcIsToken0`** from the output and set `CEILING_TICK` accordingly
(`false` → `-245880`, `true` → `245820`). Token addresses are deterministic per
(deployer, nonce), so the dry-run ordering matches the real broadcast from the same
deployer. The script reverts early if the `CEILING_TICK` sign is wrong.

## 1) Mock system

```bash
MOCK=true VRF_SUB_ID=<subId> \
  forge script scripts/DeployBase.s.sol:DeployBase \
  --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
```
Deploys MockUSDC (mints 10B to the deployer), `MockToken`/`MockNFT`, mines +
CREATE2-deploys `MockHook`, deploys `MockManager` + **`MockRound1..28`**, wires
them, seeds 1,000 MockUSDC, `init`, `start`, and **prints every address**.

Then:
1. **VRF** — add the printed `MANAGER` as a consumer on your Chainlink sub + LINK-fund it.
2. **Check `usdcIsToken0`** in the output. If `true`, the default `CEILING_TICK`
   sign is likely wrong → run
   `USDC=<MockUSDC> TMP=<MockToken> npx tsx scripts/calculate-ceiling-tick.ts`,
   pass it as `CEILING_TICK=…`, and re-run.

### Wire the off-chain stack (`themoonpot`)
3. **Contracts** — fill the printed addresses into `packages/contracts/src/mock.ts` (Manager/Token/NFT/Hook/USDC + **Rounds 1–28**).
4. **Relayer** — add `mainnet-signer-mock` + `base-mainnet-relayer-mock` in `infra/relayer/config.json`; fund that wallet.
5. **API (mock instance)** — `NETWORK=mock`, `OZ_RELAYER_ID=base-mainnet-relayer-mock`, Base RPC, its own `OZ_WEBHOOK_SECRET` + `DATABASE_URL`.
6. **Monitor** — set the `MANAGER` address in the five `monitors/*_mock.json`, set `WEBHOOK_PROCESS_URL_MOCK` + `WEBHOOK_SECRET_MOCK` (secret = the mock API's `OZ_WEBHOOK_SECRET`), flip `paused:false`, `docker compose restart monitor`.
7. **Validate** — drive a buy → `PurchaseCommitted` → VRF → `PurchaseSeedDrawn` → mock webhook → `processBuy` → `PurchaseFilled`. ✅

---

## 2) Production system

Only after the mock validates. The deployer must hold **1,000 real USDC**, and you
pass the **Safe**:

```bash
SAFE=0xYourSafe VRF_SUB_ID=<subId> \
  forge script scripts/DeployBase.s.sol:DeployBase \
  --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
```
Same one-shot, with real USDC + real `Moonpot*` contracts, and ownership of every
contract transferred to the Safe at the end.

Then:
1. **Accept ownership (Safe)** — see the next section. **Required**, or the deployer EOA stays owner.
2. **VRF** — add `MANAGER` as a consumer + LINK-fund the sub (the Safe should own the subscription).
3. **Contracts** — update `packages/contracts/src/mainnet.ts` (Manager/Token/NFT/Hook + Rounds 1–28 + pool id).
4. **Relayer** — `mainnet-signer-prod` / `base-mainnet-relayer-prod`; fund it.
5. **API (prod)** — `NETWORK=mainnet`, `OZ_RELAYER_ID=base-mainnet-relayer-prod`, prod `OZ_WEBHOOK_SECRET` / `WEBHOOK_PROCESS_URL`.
6. **Monitor** — the five prod monitors point at `MANAGER`, `paused:false`, restart.

---

## Multisig (Safe) ownership

`forge` signs from **one EOA** — it cannot sign as a Safe. So the EOA deploys and
wires everything (it needs transient ownership to call `setManager` / `setRound` /
`init` / `start`), then the script **transfers ownership to the Safe**.

Every contract is **2-step ownable** (OZ `Ownable2Step` / Chainlink
`ConfirmedOwner`), so `transferOwnership(SAFE)` only **proposes** the Safe. The
Safe must then **accept**:

> ⚠️ Until the Safe accepts, the **deployer EOA is still owner** — keep that key
> until acceptance is confirmed on-chain.

**In Safe{Wallet} → Transaction Builder, batch one transaction that calls:**
- `acceptOwnership()` on **TMP**
- `acceptOwnership()` on **NFT**
- `acceptOwnership()` on **HOOK**
- `acceptOwnership()` on **MANAGER**

After that the Safe controls everything privileged (round management,
`harvestFees`, `setVRFParams`, `setCompany`, …) and the EOA has zero authority.
The EOA only ever held gas + the seed transiently.

---

## Gotchas

- **`CEILING_TICK` is sign-sensitive to token ordering.** This one input flips sign
  depending on whether USDC sorts above/below TMP, and a wrong sign does **not**
  revert in `init` — it silently misconfigures the LP ceiling. The script guards
  against this (reverts early if the sign mismatches the deployed ordering); always
  dry-run first to learn `usdcIsToken0` and set the right value (`false` → -245880,
  `true` → 245820).
- **Never share a webhook URL/secret between mock and prod** — `purchaseId` is a
  per-Manager counter, so a mock `purchaseId=5` webhook would otherwise fire
  `processBuy(5)` on the prod Manager. Mock uses its own URL/secret → its own API.
- **VRF consumer** must be added to the subscription after each deploy (the script
  can't — the sub owner does it).
- **28 deploys in one script** — `--broadcast` sends ~90 txs (28 rounds + the rest).
  Make sure the deployer has enough ETH for gas.

---

## Note for the audit

This deploy includes changes/additions to the audited contracts that warrant a
Hacken note (logic unchanged in each case):

- **Token name** `"The Moonpot"` — set in the `MoonpotToken` constructor; the name
  lives in storage, so the **runtime bytecode is identical** to what was audited
  (only the constructor literal + stored string change).
- **Rounds 6–28** — 23 new round contracts that mirror the audited Round 1–5 pattern
  exactly (same `AbstractMoonpotRound` base + `permute`); only the immutable
  price/allocation/share values and the prize-table magnitudes differ (each pool =
  $1.00 × allocation, prize table = Round-1 shape × allocation/1M).
- **Mock\* contracts** — test-only subclasses; only deployed when `MOCK=true`.
- **Ownership handoff** — the script calls `transferOwnership(SAFE)` on all four
  ownable contracts (no contract change; uses the existing 2-step owner functions).
