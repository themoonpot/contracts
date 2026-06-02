#!/usr/bin/env bash
#
# Boots a local Anvil fork of Base mainnet, deploys the full Moonpot system to
# it (real Uniswap v4 + Permit2 from the fork; mock USDC + mock VRF), and prints
# the commands to drive a buy -> VRF fulfill -> processBuy end to end.
#
# Requires: foundry (anvil, forge, cast) and a Base mainnet RPC.
#
#   BASE_RPC_URL=https://<base-rpc> ./script/local-fork.sh
#   BASE_RPC_URL=... BASE_FORK_BLOCK=33000000 ./script/local-fork.sh   # pinned
#
set -euo pipefail

: "${BASE_RPC_URL:?Set BASE_RPC_URL to a Base mainnet RPC (Alchemy/QuickNode recommended; the public node rate-limits forking)}"
RPC="http://127.0.0.1:8545"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# 1. Start Anvil fork (reuse if one is already listening on :8545).
if cast block-number --rpc-url "$RPC" >/dev/null 2>&1; then
  echo "Reusing Anvil already listening on $RPC"
else
  echo "Starting Anvil fork of Base..."
  ANVIL_ARGS=(--fork-url "$BASE_RPC_URL" --silent)
  [ -n "${BASE_FORK_BLOCK:-}" ] && ANVIL_ARGS+=(--fork-block-number "$BASE_FORK_BLOCK")
  nohup anvil "${ANVIL_ARGS[@]}" >/tmp/moonpot-anvil.log 2>&1 &
  ANVIL_PID=$!
  echo "  anvil pid=$ANVIL_PID (log: /tmp/moonpot-anvil.log)"
  for _ in $(seq 1 40); do
    cast block-number --rpc-url "$RPC" >/dev/null 2>&1 && break
    sleep 0.5
  done
  cast block-number --rpc-url "$RPC" >/dev/null 2>&1 || { echo "Anvil failed to start; see /tmp/moonpot-anvil.log"; exit 1; }
fi

# 2. Deploy the system to the fork.
echo "Deploying Moonpot system to the fork..."
forge script script/DeployLocal.s.sol:DeployLocal \
  --rpc-url "$RPC" --broadcast --slow

cat <<EOF

------------------------------------------------------------------------------
Deployed. Copy the addresses logged above into env vars, then drive a buy:

  export MANAGER=0x...   USDC=0x...   VRF=0x...   NFT=0x...
  forge script script/DriveBuy.s.sol:DriveBuy --rpc-url $RPC --broadcast

That runs approve -> buyFor -> vrf.fulfill -> processBuy and prints the NFTs
minted to the buyer. Anvil keeps running; stop it with:  kill %1  (or the pid above)
------------------------------------------------------------------------------
EOF
