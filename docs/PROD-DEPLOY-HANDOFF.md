# Handoff — Production deploy of Moonpot on Base

Status as of this handoff: the **mock system is deployed to Base mainnet and
validated end-to-end on staging** (buys → real Chainlink VRF → relayer
`processBuy` → round sold out + seeded → claims). Round economics verified for
all 28 rounds. **Next step: deploy the real production system.**

Read this top-to-bottom, then follow [`DEPLOY.md`](./DEPLOY.md) §2 for the exact
deploy command. This doc adds the session-specific context that isn't in the
runbook.

---

## Repos & branches

- **Contracts** — `/Users/paksa/git/tmp-contracts`, branch **`deploy`**.
  One-shot deployer [`scripts/DeployBase.s.sol`](../scripts/DeployBase.s.sol),
  28 round contracts, `Mock*` test subclasses, the runbook
  [`DEPLOY.md`](./DEPLOY.md), and verification/driver scripts in `scripts/`.
- **Off-chain (monorepo)** — `/Users/paksa/git/themoonpot`, branch **`v2`**.
  frontend-v2 + api + infra (relayer/monitor/postgres docker stack). Contract
  addresses + per-network on-chain config live in
  `packages/contracts/src/{mainnet,mock,...}.ts` + `config.ts`.

---

## The single-knob network model (important)

Contract selection is one env var: **`NETWORK`** (api) / **`VITE_NETWORK`**
(frontend) ∈ `local|testnet|mock|mainnet`.
- Addresses come from `packages/contracts/src/<network>.ts`.
- Pool id + deploy block + `usdcIsToken0` come from
  `packages/contracts/src/config.ts` `getNetworkConfig(network)` (defined for the
  *fixed* deployments mock + mainnet).
- So pointing the prod stack at the real contracts = set `mainnet.ts` addresses,
  update the `mainnet` entry in `config.ts`, and run with `NETWORK=mainnet`.

Env files are environment-specific and **dotenvx-encrypted**, coexisting on every
branch (merge-safe): api `.env` = prod / `.env.staging` = mock (loaded via
`APP_ENV` in `apps/api/_start.cjs`); frontend `.env.production` = prod /
`.env.staging` = mock (`build` vs `build:staging`). **Always start the docker
stack via `dotenvx run -- docker compose …`** — bare `docker compose` substitutes
the encrypted ciphertext and breaks postgres + the relayer keystore decrypt.

---

## Pre-deploy checklist (confirm before broadcasting)

1. **Safe** multisig address (receives ownership of TMP/NFT/Hook/Manager).
2. **Deployer EOA** in the Foundry keystore (`--account moonpot-deployer`),
   funded with **Base ETH for gas** (~90 txs) and holding **`INITIAL_USDC`** of
   **real Circle USDC** (default 1,000) for the LP seed — confirm the seed size.
3. **Chainlink VRF v2.5 subscription** (`VRF_SUB_ID`), LINK-funded; the Safe
   should own it.
4. **`CEILING_MULTIPLIER`** — currently `10` (constant in `DeployBase.s.sol`); the
   LP position spans floor → 10× the final round price. Higher = deeper upside
   liquidity but more TMP minted into the LP. Confirm 10× is wanted (it's still a
   constant; change it there if not).
5. `COMPANY` fee recipient — defaults to `SAFE` if set.
6. Real USDC on Base: `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`.

## Deploy (production)

```bash
SAFE=0xYourSafe VRF_SUB_ID=<subId> \
  forge script scripts/DeployBase.s.sol:DeployBase \
  --rpc-url "$BASE_RPC_URL" --account moonpot-deployer --broadcast --verify
```
`MOCK` unset → real `Moonpot*` contracts + real USDC. Always **dry-run first**
(same command without `--broadcast`) — it prints every address, the POOL ID, and
the auto-computed CEILING TICK. The ceiling tick is computed in-script (sign-aware
for token ordering); nothing to set.

---

## Post-deploy wiring

1. **Accept ownership (Safe)** — every contract is 2-step ownable, so the deploy
   only *proposes* the Safe. In Safe Transaction Builder, batch `acceptOwnership()`
   (selector `0x79ba5097`) on **TMP, NFT, HOOK, MANAGER**. Until accepted, the
   deployer EOA is still owner. (See the mock `safe-accept-ownership-mock.json`
   pattern — make a prod copy with the printed addresses.)
2. **VRF** — add the printed `MANAGER` as a consumer on the sub + LINK-fund.
3. **`packages/contracts/src/mainnet.ts`** — set Manager/Token/NFT/Hook + Round
   1–28 addresses from the deploy report.
4. **`packages/contracts/src/config.ts`** — update the `mainnet` entry: `poolId`
   (printed POOL ID) + `deployBlock` (the deploy block). `usdcIsToken0` is derived
   from the addresses.
5. **API (prod)** — `NETWORK=mainnet`, `OZ_RELAYER_ID=base-mainnet-relayer-prod`,
   prod `OZ_WEBHOOK_SECRET` + `OZ_WEBHOOK_PROCESS_URL`, prod `DATABASE_URL`. Deploy
   = `pm2 deploy ecosystem.config.js production` (builds, runs `db:migrate`,
   reloads `frontend,api`). The prod postgres db must exist (initdb script handles
   fresh volumes; else `createdb`).
6. **Relayer (prod)** — `mainnet-signer-prod` / `base-mainnet-relayer-prod` in
   `infra/relayer/config.json` (unpaused); fund that EOA with Base ETH. Recreate
   the docker stack via `dotenvx run -- docker compose up -d --force-recreate`.
7. **Monitors (prod)** — point the 5 prod monitors (`monitors/*.json`, not the
   `*_mock.json`) at the prod `MANAGER`, `paused:false`; webhook trigger uses
   `WEBHOOK_PROCESS_URL` / `WEBHOOK_SECRET` (prod, not the `_STAGING` ones).
8. **Frontend (prod)** — `.env.production` `VITE_NETWORK=mainnet`; build/deploy.

---

## Verify the deploy

Scripts in `tmp-contracts/scripts/` (point `MANAGER=<prod manager>`):
- **`verify-config.mjs`** — all 28 rounds' numbers (99991 NFTs, table sums to
  pool, prizes scale, + a program-wide TOTALS row). Cheap, run straight against
  Base: `MANAGER=0x… RPC_URL=$BASE_RPC node scripts/verify-config.mjs`. Expect
  `28/28 rounds OK` and totals ≈ 6B TMP / $6B prizes / $600M company / ~$3.9B
  liquidity / ~$10.5B raised.
- **`verify-rounds.mjs`** — full `valueOf` sweep proving the permutation
  distributes the table (run on a round once it's sold out + seeded).
- **`drive-mock.mjs`** — auto buy + alternating single/batch claim driver (was
  used to validate the mock; works against prod too, or a local fork for speed:
  `anvil --fork-url $BASE_RPC --chain-id 8453`).

---

## Reference: the mock deployment (Base mainnet, already live)

Leave it as-is (it's the staging test system). Prod gets fresh addresses.
- MockManager `0x7a8e4920C3cc2754C5D40e60f05E82572a098c36`, MockToken
  `0x436D2572b52eB397f2033345ABB109677b1bC663`, MockNFT
  `0xfdc8C22B0239B0E9be296374D5EAA481f03aB0d4`, MockHook
  `0xACCa12d3D39662f2e7363C54d25765d910482088`, MockUSDC
  `0x440bf836e34d070Abd4C140ca6B991669Fe69EFa`.
- Pool id `0x1a643f81e8f0b7f1af2a542c326524f4a729198df96d4a24da9f4374ba3c062e`,
  deploy block `47063744`, `usdcIsToken0=false`, relayer signer
  `0x84472cd59d9b1d513281fb764280618ae5c2eb13` (`base-mainnet-relayer-v2`).

## Notes / gotchas learned this session

- **dotenvx + docker compose**: bare `docker compose` passes encrypted ciphertext
  for `${POSTGRES_USER}` / `${OZ_KEYSTORE_PWD}` → postgres initdb + relayer signer
  decrypt fail. Always `dotenvx run -- docker compose …`.
- **claim gas**: `claimNFTs` is ~600k+ gas/NFT; the frontend claim-all now
  estimates gas (was a fixed 3M tier that failed at 12 NFTs). A single tx caps
  around a few dozen NFTs; large holders need chunking (not yet built).
- **Economics**: the mint-at-floor / sell-into-LP concern is defeated by the
  defense sell tax (~35% at the +1200-tick seed); deeper analysis (prizes lower
  effective TMP cost) is bounded by the thin LP USDC + burn — floor always holds,
  not a drain. See the discussion if stakeholders revisit.
- Open frontend item: claim-all over hundreds/thousands of NFTs needs batch
  chunking; `apps/frontend/*` (v1) is being replaced by frontend-v2 and was left
  untouched.
