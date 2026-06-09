// Read-only verifier for the deployed system (mock or prod): for each seeded
// round, confirms exactly getNFTCount() NFTs were minted and that the sum of
// every NFT's valueOf() equals the round's pool (tokenCount * communityShare,
// e.g. $1,000,000 for round 1). No wallet/txs — pure eth_call, so point it at a
// local fork (fast) or Base directly.
//
//   RPC_URL=http://127.0.0.1:8545 node scripts/verify-rounds.mjs        # all seeded rounds
//   ROUNDS=1 RPC_URL=... node scripts/verify-rounds.mjs                  # just round 1
//   ROUNDS=1-3 ... / ROUNDS=1,2,5 ...                                    # ranges / lists
// Tunables: MC_BATCH (valueOf calls per multicall, default 500),
//   EXPECTED_NFTS (default 99991), MANAGER/NFT (default mock addresses).
import {
  createPublicClient,
  http,
  parseAbi,
  getAddress,
  formatUnits,
} from "viem";
import { base } from "viem/chains";

const need = (k) => {
  const v = process.env[k];
  if (!v) throw new Error(`missing env ${k}`);
  return v;
};

const RPC_URL = need("RPC_URL");
const MANAGER = getAddress(
  process.env.MANAGER ?? "0x7a8e4920C3cc2754C5D40e60f05E82572a098c36",
);
const NFT = getAddress(
  process.env.NFT ?? "0xfdc8C22B0239B0E9be296374D5EAA481f03aB0d4",
);
const MC_BATCH = Number(process.env.MC_BATCH ?? "500");
const EXPECTED_NFTS = BigInt(process.env.EXPECTED_NFTS ?? "99991");

const managerAbi = parseAbi([
  "function _currentRoundId() view returns (uint256)",
  "function rounds(uint256) view returns (address)",
]);
const nftAbi = parseAbi([
  "function getRound(uint256 tokenId) view returns (uint256)",
]);
const roundAbi = parseAbi([
  "function getSeed() view returns (uint256)",
  "function getNFTCount() view returns (uint256)",
  "function getNFTsMinted() view returns (uint256)",
  "function getTokenCount() view returns (uint256)",
  "function getCommunityShare() view returns (uint256)",
  "function valueOf(uint256 tokenId) view returns (uint256 value, uint8 classId, uint32 drawId)",
]);

const pub = createPublicClient({ chain: base, transport: http(RPC_URL) });
const read = (address, abi, functionName, args) =>
  pub.readContract({ address, abi, functionName, args });

function parseRounds(spec, current) {
  if (!spec || spec === "all")
    return Array.from({ length: current }, (_, i) => i + 1);
  const out = new Set();
  for (const part of spec.split(",")) {
    const m = part.trim();
    if (m.includes("-")) {
      const [a, b] = m.split("-").map(Number);
      for (let r = a; r <= b; r++) out.add(r);
    } else out.add(Number(m));
  }
  return [...out].filter((r) => r >= 1).sort((a, b) => a - b);
}

async function verifyRound(r, round, mintedCount, startId) {
  const [seed, nftCount, tokenCount, share] = await Promise.all([
    read(round, roundAbi, "getSeed"),
    read(round, roundAbi, "getNFTCount"),
    read(round, roundAbi, "getTokenCount"),
    read(round, roundAbi, "getCommunityShare"),
  ]);
  if (seed === 0n) {
    console.log(`round ${r}: not seeded yet — skip`);
    return;
  }
  const expectedPool = tokenCount * share;

  // contiguity spot-check (tokenIds are sequential, rounds mint in order)
  const owner = await read(NFT, nftAbi, "getRound", [startId]);
  if (owner !== BigInt(r))
    console.log(
      `  ⚠ getRound(${startId})=${owner}, expected ${r} — range assumption off`,
    );

  let sum = 0n;
  let counted = 0;
  const dist = new Map();
  for (let off = 0n; off < mintedCount; off += BigInt(MC_BATCH)) {
    const ids = [];
    for (let k = 0n; k < BigInt(MC_BATCH) && off + k < mintedCount; k++)
      ids.push(startId + off + k);
    const res = await pub.multicall({
      contracts: ids.map((id) => ({
        address: round,
        abi: roundAbi,
        functionName: "valueOf",
        args: [id],
      })),
    });
    for (const x of res) {
      if (x.status !== "success") continue;
      const [value, classId] = x.result;
      sum += value;
      counted += 1;
      dist.set(Number(classId), (dist.get(Number(classId)) ?? 0) + 1);
    }
  }

  const countOk = mintedCount === EXPECTED_NFTS && BigInt(counted) === mintedCount;
  const totalOk = sum === expectedPool;
  console.log(`round ${r}:`);
  console.log(
    `  NFTs minted: ${mintedCount} (getNFTCount=${nftCount}, expected ${EXPECTED_NFTS}) ${countOk ? "OK" : "MISMATCH"}`,
  );
  console.log(
    `  total reward: $${formatUnits(sum, 6)} (expected $${formatUnits(expectedPool, 6)}) ${totalOk ? "OK" : "MISMATCH"}`,
  );
  const distStr = [...dist.entries()]
    .sort((a, b) => a[0] - b[0])
    .map(([c, n]) => `${c}:${n}`)
    .join(" ");
  console.log(`  class distribution: ${distStr}`);
}

async function main() {
  const currentRoundId = Number(await read(MANAGER, managerAbi, "_currentRoundId"));
  const toVerify = parseRounds(process.env.ROUNDS, currentRoundId);
  const maxRound = Math.max(...toVerify, 1);

  // round addresses + minted counts, to derive each round's contiguous tokenId
  // range (start = sum of NFTs minted in earlier rounds; ERC721A starts at 0).
  const addr = {};
  const minted = {};
  for (let r = 1; r <= maxRound; r++) {
    addr[r] = await read(MANAGER, managerAbi, "rounds", [BigInt(r)]);
    minted[r] = await read(addr[r], roundAbi, "getNFTsMinted");
  }
  const start = {};
  let cum = 0n;
  for (let r = 1; r <= maxRound; r++) {
    start[r] = cum;
    cum += minted[r];
  }

  console.log(`manager=${MANAGER} currentRound=${currentRoundId}`);
  for (const r of toVerify) {
    if (minted[r] === 0n) {
      console.log(`round ${r}: 0 NFTs minted — skip`);
      continue;
    }
    await verifyRound(r, addr[r], minted[r], start[r]);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
