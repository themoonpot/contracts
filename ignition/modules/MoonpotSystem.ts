import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

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
  const tmp = m.contractAt("MoonpotToken", m.getParameter("tmp"), {
    id: "TMP",
  });
  const hook = m.contractAt("MoonpotHook", m.getParameter("hook"), {
    id: "Hook",
  });
  const nft = m.contract("MoonpotNFT", [], { id: "NFT" });

  const manager = m.contract("MoonpotManager", [
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
  ]);

  const setHookManager = m.call(hook, "setManager", [manager]);
  const setTmpManager = m.call(tmp, "setManager", [manager]);
  m.call(nft, "setManager", [manager]);

  const baseURI = "https://api.themoonpot.com/nft/";
  m.call(nft, "setBaseURI", [baseURI]);

  const round1 = m.contract("MoonpotRound1", [manager, usdc]);
  const round2 = m.contract("MoonpotRound2", [manager, usdc]);
  const round3 = m.contract("MoonpotRound3", [manager, usdc]);
  const round4 = m.contract("MoonpotRound4", [manager, usdc]);
  const round5 = m.contract("MoonpotRound5", [manager, usdc]);

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
