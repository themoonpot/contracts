/**
 * Script to mine a CREATE2 address for the MoonpotHook contract. Needed to
 * ensure the deployed hook address has certain bits set according to
 * Uniswap v4's tick encoding.
 */

import {
  keccak256,
  getContractAddress,
  encodeAbiParameters,
  parseAbiParameters,
  encodeDeployData,
} from "viem";
import fs from "fs";

const POOL_MANAGER = "0x498581ff718922c3f8e6a244956af099b2652b2b";
const POSITION_MANAGER = "0x7c5f5a4bbd8fd63184577525326123b519429bdc";
const USDC = "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913";
const TMP = "0x58f8c17ea286A085BBfE0fC1cfa3Ce39D410aEE0";
const OWNER = "0xda669Fb34A24E7E64Ee2d3BAe98E4734945c4cDB";
const PERMIT2 = "0x000000000022D473030F116dDEE9F6B43aC78BA3";

const CREATE2_FACTORY = "0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed";

function applyGuard(rawSalt: `0x${string}`): `0x${string}` {
  return keccak256(
    encodeAbiParameters(parseAbiParameters("bytes32"), [rawSalt]),
  );
}

async function mine() {
  const artifact = JSON.parse(
    fs.readFileSync(
      "./artifacts/contracts/MoonpotHook.sol/MoonpotHook.json",
      "utf8",
    ),
  );

  let rawBytecode = artifact.bytecode.slice(2);

  const creationCode = encodeDeployData({
    abi: artifact.abi,
    bytecode: rawBytecode as `0x${string}`,
    args: [POOL_MANAGER, POSITION_MANAGER, PERMIT2, USDC, TMP, OWNER],
  });

  const FLAGS = 8328n;
  const FLAG_MASK = 0x3fffn;

  for (let i = 0; i < 10_000_000; i++) {
    const rawSalt = ("0x" + i.toString(16).padStart(64, "0")) as `0x${string}`;
    const guardedSalt = applyGuard(rawSalt);

    const address = getContractAddress({
      from: CREATE2_FACTORY,
      salt: guardedSalt,
      bytecode: creationCode,
      opcode: "CREATE2",
    });

    if ((BigInt(address) & FLAG_MASK) === FLAGS) {
      console.log("✅ RAW SALT (put this in hardhat.config):", rawSalt);
      console.log("✅ GUARDED SALT (actual CREATE2 salt):   ", guardedSalt);
      console.log("✅ EXPECTED ADDRESS:", address);
      return;
    }
  }
}

mine();
