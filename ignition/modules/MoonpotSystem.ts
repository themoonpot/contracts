import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

// Deploy mode. `MOONPOT_MODE=mock` deploys the test NFT — distinct name/symbol
// ("Moonpot Test NFT" / "tTMPNFT") and contract name (MockMoonpotNFT) — so a
// mock deploy can never be mistaken for the real collection. Pair it with a
// MockMoonpotToken (TMPOnlySystem in the same mode) and a mock params file.
// Anything else (including unset) deploys the production system.
const MOCK = (process.env.MOONPOT_MODE ?? "production").toLowerCase() === "mock";
console.log(`[MoonpotSystem] deploy mode: ${MOCK ? "MOCK" : "production"}`);

// In mock mode each contract is deployed from its Mock* subclass — identical
// logic, distinct name — so nothing in a test deploy can be mistaken for the
// real system on explorers/wallets.
const c = (name: string) => (MOCK ? `Mock${name}` : name);

const MoonpotSystem = buildModule("MoonpotSystem", (m) => {
  const vrfCoordinator = m.getParameter("vrfCoordinator");
  const vrfKeyHash = m.getParameter("vrfKeyHash");
  const vrfSubId = m.getParameter("vrfSubId");
  const company = m.getParameter("company");
  const poolManager = m.getParameter("poolManager");
  const positionManager = m.getParameter("positionManager");
  const permit2 = m.getParameter("permit2");
  const usdcAmount = m.getParameter("usdcAmount");
  const positionTickUpper = m.getParameter("positionTickUpper");

  // `usdc` is the live Circle USDC on the target network (e.g. Base mainnet's
  // 0x833589fC...). We use the MockUSDC ABI here only because it exposes the
  // ERC20 surface we need (`transfer`, `approve`); the real USDC is NOT mocked
  // in production.
  const usdc = m.contractAt("MockUSDC", m.getParameter("usdc"), { id: "USDC" });
  const tmp = m.contractAt(c("MoonpotToken"), m.getParameter("tmp"), {
    id: "TMP",
  });
  const hook = m.contractAt(c("MoonpotHook"), m.getParameter("hook"), {
    id: "Hook",
  });
  const nft = m.contract(c("MoonpotNFT"), [], {
    id: "NFT",
  });

  const manager = m.contract(
    c("MoonpotManager"),
    [
      usdc,
      tmp,
      nft,
      company,
      vrfCoordinator,
      vrfKeyHash,
      vrfSubId,
      poolManager,
      positionManager,
      permit2,
      hook,
    ],
    { id: "Manager" },
  );

  const setHookManager = m.call(hook, "setManager", [manager]);
  const setTmpManager = m.call(tmp, "setManager", [manager]);
  m.call(nft, "setManager", [manager]);

  const baseURI = "https://api.themoonpot.com/nft/";
  m.call(nft, "setBaseURI", [baseURI]);

  const round1 = m.contract(c("MoonpotRound1"), [manager, usdc], { id: "Round1" });
  const round2 = m.contract(c("MoonpotRound2"), [manager, usdc], { id: "Round2" });
  const round3 = m.contract(c("MoonpotRound3"), [manager, usdc], { id: "Round3" });
  const round4 = m.contract(c("MoonpotRound4"), [manager, usdc], { id: "Round4" });
  const round5 = m.contract(c("MoonpotRound5"), [manager, usdc], { id: "Round5" });

  const setR1 = m.call(manager, "setRound", [1, round1], { id: "SetRound1" });
  const setR2 = m.call(manager, "setRound", [2, round2], { id: "SetRound2" });
  const setR3 = m.call(manager, "setRound", [3, round3], { id: "SetRound3" });
  const setR4 = m.call(manager, "setRound", [4, round4], { id: "SetRound4" });
  const setR5 = m.call(manager, "setRound", [5, round5], { id: "SetRound5" });

  const transferUSDC = m.call(usdc, "transfer", [manager, usdcAmount], {
    from: m.getAccount(0),
    id: "TransferUSDCToManager",
  });

  const init = m.call(manager, "init", [usdcAmount, positionTickUpper], {
    after: [
      setHookManager,
      setTmpManager,
      setR1,
      setR2,
      setR3,
      setR4,
      setR5,
      transferUSDC,
    ],
    id: "InitManager",
  });

  m.call(manager, "start", [], {
    after: [init],
  });

  return { tmp, nft, manager };
});

export default MoonpotSystem;
