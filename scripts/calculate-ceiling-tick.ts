/**
 * Offline helper. Derives `positionTickUpper` (the LP ceiling tick) from the
 * last-round price × CEILING_MULTIPLIER and the pool's tick spacing. Output is
 * already pinned in `ignition/parameters/{mainnet,test}.json`; the script is
 * here for transparency on how that value was chosen.
 *
 * Only the last entry in ROUND_PRICES affects the ceiling; the earlier entries
 * are illustrative and may not match the production round schedule.
 */

import { parseUnits, formatUnits } from "viem";

const USDC_ADDRESS = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const TMP_ADDRESS = "0x58f8c17ea286A085BBfE0fC1cfa3Ce39D410aEE0";
const TICK_SPACING = 60;
const CEILING_MULTIPLIER = 10n;
const INIT_TICK_PREMIUM = 1200;

// Actually only need the last round price, but defining extra rounds for
// reference and sanity checks
const ROUND_PRICES: Record<number, bigint> = {
  1: parseUnits("1.15", 6),
  2: parseUnits("1.30", 6),
  3: parseUnits("1.50", 6),
  4: parseUnits("1.80", 6),
  5: parseUnits("2.10", 6),
};

function priceToTick(priceUsdc: bigint, usdcIsToken0: boolean): number {
  const ratio = usdcIsToken0
    ? Number(10n ** 18n) / Number(priceUsdc) // TMP_raw / USDC_raw
    : Number(priceUsdc) / Number(10n ** 18n); // USDC_raw / TMP_raw
  return Math.floor(Math.log(ratio) / Math.log(1.0001));
}

function roundToTickSpacing(tick: number, spacing: number): number {
  const remainder = tick % spacing;
  return remainder < 0 ? tick - (spacing + remainder) : tick - remainder;
}

function main() {
  const usdcIsToken0 = USDC_ADDRESS.toLowerCase() < TMP_ADDRESS.toLowerCase();
  const lastRound = Math.max(...Object.keys(ROUND_PRICES).map(Number));
  const lastPrice = ROUND_PRICES[lastRound];
  const ceilingPrice = lastPrice * CEILING_MULTIPLIER;

  console.log(`USDC is token0:   ${usdcIsToken0}`);
  console.log(`Tick spacing:     ${TICK_SPACING}`);
  console.log();

  // Round floor ticks for reference
  console.log("── Round floor ticks ────────────────────────────────────────");
  for (const [round, price] of Object.entries(ROUND_PRICES)) {
    const tick = roundToTickSpacing(
      priceToTick(price, usdcIsToken0),
      TICK_SPACING,
    );
    console.log(
      `  Round ${round}  $${formatUnits(price, 6).padEnd(6)}  →  tick ${tick}`,
    );
  }
  console.log();

  // positionTickUpper = ceiling price tick
  const rawCeilingTick = priceToTick(ceilingPrice, usdcIsToken0);
  const positionTickUpper = roundToTickSpacing(rawCeilingTick, TICK_SPACING);

  // Init tick: above floor in price = below floor in tick when usdcIsToken0
  const round1FloorTick = roundToTickSpacing(
    priceToTick(ROUND_PRICES[1], usdcIsToken0),
    TICK_SPACING,
  );
  const rawInitTick = usdcIsToken0
    ? round1FloorTick - INIT_TICK_PREMIUM
    : round1FloorTick + INIT_TICK_PREMIUM;
  const initTick = roundToTickSpacing(rawInitTick, TICK_SPACING);

  console.log("── Key ticks ────────────────────────────────────────────────");
  console.log(
    `  Round 1 floor tick:  ${round1FloorTick}  ($${formatUnits(ROUND_PRICES[1], 6)})`,
  );
  console.log(
    `  Pool init tick:      ${initTick}          (~13% above floor in price)`,
  );
  console.log(
    `  Ceiling price:       $${formatUnits(ceilingPrice, 6)}  (${CEILING_MULTIPLIER}× round ${lastRound} price)`,
  );
  console.log(`  positionTickUpper:   ${positionTickUpper}`);
  console.log();

  // Sanity check: when USDC is token0, floor tick > ceiling tick (lower price = higher tick)
  if (usdcIsToken0 && round1FloorTick <= positionTickUpper) {
    console.warn(
      "WARNING: floor tick should be > ceiling tick when USDC is token0",
    );
  }
  if (!usdcIsToken0 && round1FloorTick >= positionTickUpper) {
    console.warn(
      "WARNING: floor tick should be < ceiling tick when TMP is token0",
    );
  }

  console.log("── Ignition parameter ───────────────────────────────────────");
  console.log(JSON.stringify({ positionTickUpper }, null, 2));
}

main();
