# Deploy runbooks — Moonpot on Base

One Foundry script — [`scripts/DeployBase.s.sol`](../scripts/DeployBase.s.sol) —
deploys the whole system to Base mainnet in a **single command**. It mines the
v4 hook salt in-script (`HookMiner`), so there are no offline mining steps,
config edits, or params files.

- **`MOCK=true`** → deploys `MockUSDC` + the de-branded `Mock*` contracts. A safe,
  clearly-distinct copy for end-to-end testing.
- **`MOCK=false`** (default) → the real `Moonpot*` contracts against live Circle
  USDC.

Both use real Chainlink VRF.

Plan: **deploy mock → validate end-to-end → deploy production.**

---

## Prerequisites

- A dedicated **deployer EOA** in the Foundry keystore and funded with **ETH on
  Base**:
  ```bash
  cast wallet new                       # note the address + key
  cast wallet import moonpot-deployer --interactive   # paste the key, set a password
  ```
  (Or pass `PRIVATE_KEY=0x…` as an env var instead of `--account`.)
- `BASE_RPC_URL` exported (Base mainnet RPC).
- `VRF_SUB_ID` — your Chainlink VRF v2.5 subscription id (required).
- For **production only**: the deployer must already hold `INITIAL_USDC`
  (default **1,000**) of **real USDC** — it's transferred as the LP seed.
- The branch you deploy from must contain the `Mock*` contracts (the unified
  script imports them) **and**, for production, the `"The Moonpot"` token-name
  change.

### Tunables (env)
| var | default | notes |
|---|---|---|
| `MOCK` | `false` | `true` = mock system |
| `VRF_SUB_ID` | — | **required** |
| `INITIAL_USDC` | `1000e6` | LP seed (base units) |
| `CEILING_TICK` | `-245880` | LP ceiling tick — recompute if ordering flips (below) |
| `COMPANY` | deployer | fee recipient |
| `VRF_COORDINATOR` / `VRF_KEY_HASH` | Base defaults | real Chainlink VRF |
| `PRIVATE_KEY` | — | alternative to `--account` |

---

## 1) Mock system

```bash
MOCK=true VRF_SUB_ID=<subId> forge script scripts/DeployBase.s.sol:DeployBase \
  --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
```
This deploys MockUSDC (mints 10B to the deployer), `MockToken`/`MockNFT`,
mines + CREATE2-deploys `MockHook`, deploys `MockManager` + `MockRound1‑5`, wires
them, seeds 1,000 MockUSDC, `init`, `start`, and **prints every address**.

Then:
1. **VRF** — add the printed `MANAGER` as a consumer on your Chainlink sub + ensure it's LINK-funded.
2. **Check `usdcIsToken0`** in the output. If it's `true`, the default
   `CEILING_TICK` sign is likely wrong → run
   `USDC=<MockUSDC> TMP=<MockToken> npx tsx scripts/calculate-ceiling-tick.ts`,
   pass the value as `CEILING_TICK=…`, and re-run.

### Wire the off-chain stack (`themoonpot`)
3. **Contracts** — fill the printed addresses into `packages/contracts/src/mock.ts`.
4. **Relayer** — add `mainnet-signer-mock` + `base-mainnet-relayer-mock` in `infra/relayer/config.json`; fund that wallet.
5. **API (mock instance)** — `NETWORK=mock`, `OZ_RELAYER_ID=base-mainnet-relayer-mock`, Base RPC, its own `OZ_WEBHOOK_SECRET` + `DATABASE_URL`.
6. **Monitor** — set the `MANAGER` address in the five `monitors/*_mock.json`, set `WEBHOOK_PROCESS_URL_MOCK` + `WEBHOOK_SECRET_MOCK` (secret = the mock API's `OZ_WEBHOOK_SECRET`), flip `paused:false`, `docker compose restart monitor`.
7. **Validate** — drive a buy → `PurchaseCommitted` → VRF → `PurchaseSeedDrawn` → mock webhook → `processBuy` → `PurchaseFilled`. ✅

---

## 2) Production system

Only after the mock validates. The deployer must hold **1,000 real USDC**.

```bash
VRF_SUB_ID=<subId> forge script scripts/DeployBase.s.sol:DeployBase \
  --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
```
(No `MOCK` → production: real USDC, real `Moonpot*` contracts.) Same one-shot:
mine + deploy hook, deploy/wire Manager + Rounds, seed, `init`, `start`, print addresses.

Then:
1. **VRF** — add `MANAGER` as a consumer + LINK-fund the sub.
2. **Contracts** — update `packages/contracts/src/mainnet.ts` with the printed addresses (+ pool id).
3. **Relayer** — `mainnet-signer-prod` / `base-mainnet-relayer-prod` (already in config); fund it.
4. **API (prod)** — `NETWORK=mainnet`, `OZ_RELAYER_ID=base-mainnet-relayer-prod`, prod `OZ_WEBHOOK_SECRET` / `WEBHOOK_PROCESS_URL`.
5. **Monitor** — the five prod monitors point at `MANAGER`, `paused:false`, restart.

---

## Gotchas

- **`CEILING_TICK` is sign-sensitive to token ordering.** The contracts handle
  `usdcIsCurrency0` dynamically, but this one deploy input flips sign depending on
  whether the USDC address sorts above/below TMP. The script prints `usdcIsToken0`
  — recompute the tick if it's unexpected.
- **Never share a webhook URL/secret between mock and prod** — `purchaseId` is a
  per-Manager counter, so a mock `purchaseId=5` webhook would otherwise fire
  `processBuy(5)` on the prod Manager. Mock uses its own URL/secret → its own API instance.
- **VRF consumer** must be added to the subscription after each deploy (the script
  can't do it — the sub owner does).

## Note on the audited contracts

The production token name (`"The Moonpot"`) is set in the `MoonpotToken`
constructor — the name lives in storage and is read by `name()`, so the **runtime
bytecode is identical to what Hacken audited**; only the constructor literal and
stored string change. Flag it as a one-string diff in the deploy record. The
`Mock*` contracts inherit the audited logic byte-for-byte (only display
name/symbol or contract name differ) and are imported by the deploy script but
**only deployed when `MOCK=true`**.
