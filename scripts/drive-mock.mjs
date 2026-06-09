// Drives the deployed MOCK system on Base mainnet: auto-buys TMP and auto-claims
// revealed NFTs, alternating single claimNFT / batch claimNFTs. Unlike
// DriveBuy.s.sol (local fork, mock VRF) this does NOT fulfill VRF or call
// processBuy — on staging those happen via real Chainlink VRF + the relayer.
// Claims only succeed once a round has fully sold out, ended, and been seeded.
//
//   RPC_URL=https://base-mainnet... PRIVATE_KEY=0x<buyer with MockUSDC + ETH> \
//   node scripts/drive-mock.mjs
//
// Tunables (env): TOKENS_PER_BUY=100  BUYS=1  CLAIM=true  CLAIM_BATCH=10
//   LOOP=true  INTERVAL_MS=15000  DEPLOY_BLOCK=47063744
//   MANAGER/USDC/NFT (default to the deployed mock addresses)
import {
  createPublicClient,
  createWalletClient,
  http,
  parseAbi,
  parseAbiItem,
  getAddress,
  maxUint256,
  zeroAddress,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";

const need = (k) => {
  const v = process.env[k];
  if (!v) throw new Error(`missing env ${k}`);
  return v;
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const ZERO32 = `0x${"0".repeat(64)}`;
const MAX_PURCHASE_LIMIT = 10_000n;

const RPC_URL = need("RPC_URL");
const account = privateKeyToAccount(need("PRIVATE_KEY"));
const MANAGER = getAddress(
  process.env.MANAGER ?? "0x7a8e4920C3cc2754C5D40e60f05E82572a098c36",
);
const USDC = getAddress(
  process.env.USDC ?? "0x440bf836e34d070Abd4C140ca6B991669Fe69EFa",
);
const NFT = getAddress(
  process.env.NFT ?? "0xfdc8C22B0239B0E9be296374D5EAA481f03aB0d4",
);
const TOKENS_PER_BUY = BigInt(process.env.TOKENS_PER_BUY ?? "100");
const BUYS = Number(process.env.BUYS ?? "1");
const CLAIM = (process.env.CLAIM ?? "true") !== "false";
const CLAIM_BATCH = Number(process.env.CLAIM_BATCH ?? "48");
const DEPLOY_BLOCK = BigInt(process.env.DEPLOY_BLOCK ?? "47063744");
// eth_getLogs block window per request (Alchemy rejects very wide ranges; the
// frontend scans in 5k windows). Lower it if your RPC still complains.
const LOG_CHUNK = BigInt(process.env.LOG_CHUNK ?? "5000");
const LOOP = (process.env.LOOP ?? "false") === "true";
const INTERVAL_MS = Number(process.env.INTERVAL_MS ?? "3600");
// Max NFTs to claim per cycle (0 = all claimable). claimNFTs is ~600k gas/NFT,
// so a big CLAIM_BATCH overflows the node's estimateGas cap — batches are sized
// to GAS_BUDGET instead of trusting CLAIM_BATCH blindly.
const CLAIM_MAX = Number(process.env.CLAIM_MAX ?? "0");
const GAS_BUDGET = BigInt(process.env.GAS_BUDGET ?? "18000000");

const usdcAbi = parseAbi([
  "function approve(address spender, uint256 amount) returns (bool)",
  "function allowance(address owner, address spender) view returns (uint256)",
  "function balanceOf(address) view returns (uint256)",
]);
const managerAbi = parseAbi([
  "function _currentRoundId() view returns (uint256)",
  "function rounds(uint256) view returns (address)",
  "function buyFor(address buyer, uint256 usdcAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s)",
  "function claimNFT(uint256 tokenId)",
  "function claimNFTs(uint256[] tokenIds)",
  "function claimed(uint256 roundId, uint256 tokenId) view returns (bool)",
]);
const roundAbi = parseAbi([
  "function getPricePerToken() view returns (uint256)",
  "function getTokenCount() view returns (uint256)",
  "function getTokensSold() view returns (uint256)",
  "function getEndTime() view returns (uint256)",
  "function getSeed() view returns (uint256)",
]);
const nftAbi = parseAbi([
  "function getRound(uint256 tokenId) view returns (uint256)",
]);
const transferEvent = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 indexed tokenId)",
);

const pub = createPublicClient({ chain: base, transport: http(RPC_URL) });
const wallet = createWalletClient({
  account,
  chain: base,
  transport: http(RPC_URL),
});

const read = (address, abi, functionName, args) =>
  pub.readContract({ address, abi, functionName, args });
const send = async (req) => {
  const hash = await wallet.writeContract(req);
  const rcpt = await pub.waitForTransactionReceipt({ hash });
  return { hash, status: rcpt.status };
};

// Send a claimNFTs batch sized to fit GAS_BUDGET: estimate, halving the chunk
// until the estimate fits (or reverts), down to a single-token claimNFT.
async function sendClaimBatch(ids) {
  let chunk = ids;
  for (;;) {
    try {
      const gas = await pub.estimateContractGas({
        address: MANAGER,
        abi: managerAbi,
        functionName: "claimNFTs",
        args: [chunk],
        account: account.address,
      });
      if (gas <= GAS_BUDGET) {
        const hash = await wallet.writeContract({
          address: MANAGER,
          abi: managerAbi,
          functionName: "claimNFTs",
          args: [chunk],
          gas: (gas * 12n) / 10n,
        });
        const rcpt = await pub.waitForTransactionReceipt({ hash });
        return { count: chunk.length, status: rcpt.status };
      }
    } catch {
      // estimate over the node's cap / reverted — shrink and retry
    }
    if (chunk.length <= 1) {
      const { status } = await send({
        address: MANAGER,
        abi: managerAbi,
        functionName: "claimNFT",
        args: [chunk[0]],
      });
      return { count: 1, status };
    }
    chunk = chunk.slice(0, Math.ceil(chunk.length / 2));
  }
}

async function buyOnce() {
  const roundId = await read(MANAGER, managerAbi, "_currentRoundId");
  const round = await read(MANAGER, managerAbi, "rounds", [roundId]);
  const [price, count, sold] = await Promise.all([
    read(round, roundAbi, "getPricePerToken"),
    read(round, roundAbi, "getTokenCount"),
    read(round, roundAbi, "getTokensSold"),
  ]);
  const available = count - sold;
  if (available <= 0n) {
    console.log(`  round ${roundId} sold out`);
    return false;
  }
  let tokens = TOKENS_PER_BUY;
  if (tokens > available) tokens = available;
  if (tokens > MAX_PURCHASE_LIMIT) tokens = MAX_PURCHASE_LIMIT;
  const usdcAmount = price * tokens;

  const allowance = await read(USDC, usdcAbi, "allowance", [
    account.address,
    MANAGER,
  ]);
  if (allowance < usdcAmount) {
    console.log("  approving USDC (max)…");
    await send({
      address: USDC,
      abi: usdcAbi,
      functionName: "approve",
      args: [MANAGER, maxUint256],
    });
  }

  const { hash, status } = await send({
    address: MANAGER,
    abi: managerAbi,
    functionName: "buyFor",
    args: [account.address, usdcAmount, 0n, 0, ZERO32, ZERO32],
  });
  console.log(
    `  bought ${tokens} TMP in round ${roundId} (${hash.slice(
      0,
      10,
    )}… ${status})`,
  );
  return true;
}

async function ownedTokenIds() {
  const latest = await pub.getBlockNumber();
  const ids = [];
  for (let from = DEPLOY_BLOCK; from <= latest; from += LOG_CHUNK + 1n) {
    const to = from + LOG_CHUNK > latest ? latest : from + LOG_CHUNK;
    const logs = await pub.getLogs({
      address: NFT,
      event: transferEvent,
      args: { from: zeroAddress, to: account.address }, // mints to us
      fromBlock: from,
      toBlock: to,
    });
    for (const l of logs) ids.push(l.args.tokenId);
  }
  return ids; // the driver never sells NFTs, so mints-to-us == owned
}

async function claimClaimables() {
  const owned = await ownedTokenIds();
  if (owned.length === 0) {
    console.log(
      "  no NFTs owned yet (buy -> VRF -> relayer processBuy mints them)",
    );
    return;
  }

  const rounds = await pub.multicall({
    contracts: owned.map((id) => ({
      address: NFT,
      abi: nftAbi,
      functionName: "getRound",
      args: [id],
    })),
  });
  const claimedFlags = await pub.multicall({
    contracts: owned.map((id, i) => ({
      address: MANAGER,
      abi: managerAbi,
      functionName: "claimed",
      args: [rounds[i].result ?? 0n, id],
    })),
  });

  const roundReady = new Map();
  const ready = async (roundId) => {
    if (roundReady.has(roundId)) return roundReady.get(roundId);
    const round = await read(MANAGER, managerAbi, "rounds", [roundId]);
    const [end, seed] = await Promise.all([
      read(round, roundAbi, "getEndTime"),
      read(round, roundAbi, "getSeed"),
    ]);
    const ok = end > 0n && seed > 0n;
    roundReady.set(roundId, ok);
    return ok;
  };

  const claimable = [];
  for (let i = 0; i < owned.length; i++) {
    if (rounds[i].status !== "success" || claimedFlags[i].status !== "success")
      continue;
    const roundId = rounds[i].result;
    if (roundId === 0n || claimedFlags[i].result) continue;
    if (await ready(roundId)) claimable.push(owned[i]);
  }

  if (claimable.length === 0) {
    console.log(
      `  own ${owned.length} NFTs, 0 claimable (rounds must end + be seeded)`,
    );
    return;
  }

  const toClaim = CLAIM_MAX > 0 ? claimable.slice(0, CLAIM_MAX) : claimable;
  console.log(
    `  claiming ${toClaim.length} of ${claimable.length} claimable NFTs (alternating single/batch)…`,
  );
  let i = 0;
  let batch = false;
  let done = 0;
  let skipped = 0;
  while (i < toClaim.length) {
    try {
      if (!batch) {
        const id = toClaim[i];
        const { status } = await send({
          address: MANAGER,
          abi: managerAbi,
          functionName: "claimNFT",
          args: [id],
        });
        console.log(`    single claimNFT(${id}) ${status}`);
        i += 1;
        done += 1;
      } else {
        const { count, status } = await sendClaimBatch(
          toClaim.slice(i, i + CLAIM_BATCH),
        );
        console.log(`    batch claimNFTs([${count}]) ${status}`);
        i += count;
        done += count;
      }
    } catch (e) {
      // skip + surface the raw node reason (shortMessage is just "invalid params")
      const reason =
        e?.details ??
        e?.cause?.details ??
        e?.metaMessages?.join(" ") ??
        e?.shortMessage ??
        e?.message ??
        String(e);
      console.log(`    skip ${toClaim[i]}: ${reason}`);
      i += 1;
      skipped += 1;
    }
    batch = !batch;
  }
  console.log(`  done: claimed ${done}, skipped ${skipped}`);
}

async function cycle() {
  for (let i = 0; i < BUYS; i++) if (!(await buyOnce())) break;
  if (CLAIM) await claimClaimables();
}

async function main() {
  const usdcBal = await read(USDC, usdcAbi, "balanceOf", [account.address]);
  console.log(`driver buyer=${account.address} MockUSDC bal=${usdcBal}`);
  console.log(
    `manager=${MANAGER} loop=${LOOP} buys/cycle=${BUYS} tokens/buy=${TOKENS_PER_BUY}`,
  );
  do {
    try {
      await cycle();
    } catch (e) {
      console.error("cycle error:", e?.shortMessage ?? e?.message ?? e);
    }
    if (LOOP) await sleep(INTERVAL_MS);
  } while (LOOP);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
