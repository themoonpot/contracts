// Read-only CONFIG verifier for every round (no seed/NFTs needed, no sweep).
// Round 1's full valueOf sweep (verify-rounds.mjs) already proves the permutation
// distributes the table correctly; rounds 2-28 share the identical
// AbstractMoonpotRound logic, so for them it suffices to verify the configured
// numbers: 99991 NFTs, the prize table sums to the pool, and prizes scale
// (round1 prize x allocation/1M). ~32 getNFTClass reads per round, so it runs
// fine straight against Base.
//
//   RPC_URL=https://base-mainnet... node scripts/verify-config.mjs
//   ROUNDS=1-28 / ROUNDS=7 ...   MANAGER=0x.. (default mock)
import { createPublicClient, http, parseAbi, getAddress, formatUnits } from "viem";
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
const MAX_ROUNDS = Number(process.env.MAX_ROUNDS ?? "28");

const COMMUNITY = 1_000_000n; // $1.00 / token (flat, all rounds)
const COMPANY = 100_000n; //   $0.10 / token (flat)
const NFT_TOTAL = 99_991n;
// Fixed class shape (counts) shared by every round; only prizes scale.
const COUNTS = [1, 2, 3, 5, 10, 20, 50, 100, 300, 500, 1000, 3000, 5000, 10000, 30000, 50000];
const CUM = (() => {
  const out = [];
  let a = 0;
  for (const c of COUNTS) {
    a += c;
    out.push(a);
  }
  return out; // [1,3,6,...,99991]
})();

const managerAbi = parseAbi([
  "function rounds(uint256) view returns (address)",
]);
const roundAbi = parseAbi([
  "function getPricePerToken() view returns (uint256)",
  "function getTokenCount() view returns (uint256)",
  "function getNFTCount() view returns (uint256)",
  "function getCommunityShare() view returns (uint256)",
  "function getCompanyShare() view returns (uint256)",
  "function getNFTClass(uint32 index) view returns ((uint8 classId, uint128 usdcValue))",
]);

const pub = createPublicClient({ chain: base, transport: http(RPC_URL) });
const read = (address, abi, functionName, args) =>
  pub.readContract({ address, abi, functionName, args });
const usd = (x) =>
  "$" +
  Number(formatUnits(x, 6)).toLocaleString("en-US", { maximumFractionDigits: 2 });

function parseRounds(spec) {
  if (!spec || spec === "all")
    return Array.from({ length: MAX_ROUNDS }, (_, i) => i + 1);
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

// getNFTClass at last-of-class (cum-1) + first-of-next (cum) for each class.
async function readTable(round) {
  const idx = [];
  for (let i = 0; i < 16; i++) {
    idx.push(CUM[i] - 1);
    idx.push(CUM[i]);
  }
  const res = await pub.multicall({
    contracts: idx.map((index) => ({
      address: round,
      abi: roundAbi,
      functionName: "getNFTClass",
      args: [index],
    })),
    allowFailure: false,
  });
  const at = new Map();
  idx.forEach((index, k) => {
    const r = res[k];
    at.set(index, { classId: Number(r.classId ?? r[0]), value: BigInt(r.usdcValue ?? r[1]) });
  });
  return at;
}

async function verifyRound(r, round, base) {
  const [price, tokenCount, nftCount, community, company] = await Promise.all([
    read(round, roundAbi, "getPricePerToken"),
    read(round, roundAbi, "getTokenCount"),
    read(round, roundAbi, "getNFTCount"),
    read(round, roundAbi, "getCommunityShare"),
    read(round, roundAbi, "getCompanyShare"),
  ]);
  const pool = tokenCount * community;
  const table = await readTable(round);

  const errs = [];
  if (nftCount !== NFT_TOTAL) errs.push(`NFT count ${nftCount} != ${NFT_TOTAL}`);
  if (community !== COMMUNITY) errs.push(`community ${community} != ${COMMUNITY}`);
  if (company !== COMPANY) errs.push(`company ${company} != ${COMPANY}`);
  const liquidity = price - community - company;
  if (liquidity < 0n) errs.push(`liquidity share negative (price ${price})`);
  if (tokenCount % 1_000_000n !== 0n)
    errs.push(`tokenCount ${tokenCount} not a whole-million allocation`);
  const mult = tokenCount / 1_000_000n;

  // class boundaries + prizes
  const prizes = [];
  for (let i = 0; i < 16; i++) {
    const last = table.get(CUM[i] - 1); // last NFT of class i+1
    const next = table.get(CUM[i]); //     first NFT of class i+2 (or None)
    if (last.classId !== i + 1)
      errs.push(`class@${CUM[i] - 1} = ${last.classId}, expected ${i + 1}`);
    const expectNext = i < 15 ? i + 2 : 0; // last boundary -> None (draw >= total)
    if (next.classId !== expectNext)
      errs.push(`boundary@${CUM[i]} = ${next.classId}, expected ${expectNext}`);
    prizes.push(last.value);
  }

  // table totals + scaling vs round 1
  let tableSum = 0n;
  for (let i = 0; i < 16; i++) tableSum += BigInt(COUNTS[i]) * prizes[i];
  if (tableSum !== pool)
    errs.push(`table sum $${formatUnits(tableSum, 6)} != pool $${formatUnits(pool, 6)}`);
  if (base) {
    for (let i = 0; i < 16; i++) {
      if (prizes[i] !== base[i] * mult)
        errs.push(
          `class ${i + 1} prize $${formatUnits(prizes[i], 6)} != $${formatUnits(base[i] * mult, 6)} (base x${mult})`,
        );
    }
  }

  const raised = tokenCount * price;
  const companyTotal = tokenCount * company;
  const liquidityTotal = tokenCount * liquidity;

  const tag = errs.length === 0 ? "OK  " : "FAIL";
  console.log(
    `round ${String(r).padStart(2)}: ${tag}  price $${formatUnits(price, 6)}  alloc ${String(tokenCount / 1_000_000n).padStart(4)}M  NFTs ${nftCount}  raised ${usd(raised).padStart(15)}  prizes ${usd(pool).padStart(15)}`,
  );
  for (const e of errs) console.log(`         - ${e}`);
  return {
    ok: errs.length === 0,
    prizes,
    tokenCount,
    nftCount,
    pool,
    raised,
    companyTotal,
    liquidityTotal,
  };
}

async function main() {
  const toVerify = parseRounds(process.env.ROUNDS);
  console.log(`manager=${MANAGER}  rounds=${toVerify[0]}..${toVerify[toVerify.length - 1]}`);

  // round 1 is the scaling base
  const round1 = await read(MANAGER, managerAbi, "rounds", [1n]);
  const r1 = await verifyRound(1, round1, null);
  const base = r1.prizes;

  const totals = { alloc: 0n, nfts: 0n, pool: 0n, raised: 0n, company: 0n, liquidity: 0n };
  const add = (f) => {
    totals.alloc += f.tokenCount;
    totals.nfts += f.nftCount;
    totals.pool += f.pool;
    totals.raised += f.raised;
    totals.company += f.companyTotal;
    totals.liquidity += f.liquidityTotal;
  };

  let pass = 0;
  let total = 0;
  if (toVerify.includes(1)) {
    total += 1;
    if (r1.ok) pass += 1;
    add(r1);
  }
  for (const r of toVerify) {
    if (r === 1) continue;
    const round = await read(MANAGER, managerAbi, "rounds", [BigInt(r)]);
    if (round === "0x0000000000000000000000000000000000000000") {
      console.log(`round ${r}: not set — stop`);
      break;
    }
    const f = await verifyRound(r, round, base);
    total += 1;
    if (f.ok) pass += 1;
    add(f);
  }

  console.log(
    `\nTOTALS (${total} rounds): raised ${usd(totals.raised)}  alloc ${totals.alloc / 1_000_000n}M TMP  NFTs ${totals.nfts}  prizes ${usd(totals.pool)}  company ${usd(totals.company)}  liquidity ${usd(totals.liquidity)}`,
  );
  console.log(`${pass}/${total} rounds OK`);
  if (pass !== total) process.exit(1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
