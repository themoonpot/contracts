#!/usr/bin/env bash
#
# Boots a local Anvil fork of Base mainnet, deploys the full Moonpot system to
# it (real Uniswap v4 + Permit2 from the fork; mock USDC + mock VRF), and prints
# the commands to drive a buy -> VRF fulfill -> processBuy end to end.
#
# Requires: foundry (anvil, forge, cast) and a Base mainnet RPC.
#
#   BASE_RPC_URL=https://<base-rpc> ./scripts/local-fork.sh
#   BASE_RPC_URL=... BASE_FORK_BLOCK=33000000 ./scripts/local-fork.sh   # pinned
#
set -euo pipefail

: "${BASE_RPC_URL:?Set BASE_RPC_URL to a Base mainnet RPC (Alchemy/QuickNode recommended; the public node rate-limits forking)}"
RPC="http://127.0.0.1:8545"
# Dedicated local deployer (fresh key -> nonce 0 -> deterministic addresses).
# Must match DEFAULT_DEPLOYER_KEY in DeployLocal.s.sol / DriveBuy.s.sol.
DEPLOYER_KEY="${PRIVATE_KEY:-0xb0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. Start Anvil fork (reuse if one is already listening on :8545).
if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "Reusing Anvil already listening on $RPC"
else
  echo "Starting Anvil fork of Base..."
  # Pin a block by default so the deploy block is reproducible (the frontend's
  # VITE_DEPLOY_BLOCK must match it). Needs an archive-capable RPC (Alchemy's
  # free Base tier works); set BASE_FORK_BLOCK= to fork at latest instead.
  FORK_BLOCK="${BASE_FORK_BLOCK-33000000}"
  # Override the chain id (31337) so wallets treat the fork as a distinct
  # network from real Base — avoids RPC collisions / accidental mainnet txs.
  ANVIL_ARGS=(--fork-url "$BASE_RPC_URL" --chain-id 31337 --silent)
  [ -n "$FORK_BLOCK" ] && ANVIL_ARGS+=(--fork-block-number "$FORK_BLOCK")
  nohup anvil "${ANVIL_ARGS[@]}" >/tmp/moonpot-anvil.log 2>&1 &
  ANVIL_PID=$!
  echo "  anvil pid=$ANVIL_PID (log: /tmp/moonpot-anvil.log)"
  for _ in $(seq 1 40); do
    cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
    sleep 0.5
  done
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || { echo "Anvil failed to start; see /tmp/moonpot-anvil.log"; exit 1; }
fi

# 2. Fund the deployer (fresh key has no balance on the fork).
DEPLOYER_ADDR="$(cast wallet address --private-key "$DEPLOYER_KEY")"
echo "Funding deployer $DEPLOYER_ADDR with 10000 ETH..."
cast rpc anvil_setBalance "$DEPLOYER_ADDR" 0x21e19e0c9bab2400000 --rpc-url "$RPC" >/dev/null

# 3. Deploy the system to the fork (deterministic addresses from the fresh deployer).
echo "Deploying Moonpot system to the fork..."
PRIVATE_KEY="$DEPLOYER_KEY" forge script scripts/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC" --broadcast --slow

cat <<EOF

------------------------------------------------------------------------------
Deployed (addresses are deterministic across runs with this deployer). Drive a
full buy -> VRF fulfill -> processBuy with the addresses logged above:

  export MANAGER=0x...   USDC=0x...   VRF=0x...   NFT=0x...
  forge script scripts/DriveBuy.s.sol:DriveBuy --rpc-url $RPC --broadcast --slow

Anvil keeps running; stop it with:  kill %1  (or the pid above)
------------------------------------------------------------------------------
EOF
