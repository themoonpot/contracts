import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const HookOnlySystem = buildModule("HookOnlySystem", (m) => {
  const poolManager = m.getParameter("poolManager");
  const positionManager = m.getParameter("positionManager");
  const permit2 = m.getParameter("permit2");
  const usdc = m.getParameter("usdc");
  const tmp = m.getParameter("tmp");
  const owner = m.getParameter("owner");

  const hook = m.contract("MoonpotHook", [
    poolManager,
    positionManager,
    permit2,
    usdc,
    tmp,
    owner,
  ]);

  return { hook };
});

export default HookOnlySystem;
